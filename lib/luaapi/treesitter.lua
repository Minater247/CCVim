-- Treesitter compatibility layer with pluggable language backends.
--
-- This module provides an extensible parser/highlighter backend interface.
-- Lua is implemented as the first backend; additional languages can register
-- backend adapters without changing the public API surface.

local M = {}
local LANGUAGE_VERSION = 1
local MINIMUM_LANGUAGE_VERSION = 1

local api = loadModule("lib.luaapi.api")
local options = loadModule("lib.options")
local scopes = loadModule("lib.luaapi.scopes")
local package = loadModule("lib.luaapi.package")
local Highlight = loadModule("lib.highlight")

local parser_by_buf = {}
local query_overrides = {}

local backend_by_lang = {}
local filetypes_by_lang

local function copy_list(src)
    local out = {}
    for i = 1, #(src or {}) do
        out[i] = src[i]
    end
    return out
end

local function resolve_bufnr(bufnr)
    if bufnr == nil or bufnr == 0 then
        return api.nvim_get_current_buf()
    end
    return bufnr
end

local function get_buffer(bufnr)
    return buffers[bufnr]
end

local function set_buffer_var(bufnr, name, value)
    local t = scopes._b_by_buf[bufnr]
    if not t then
        t = {}
        scopes._b_by_buf[bufnr] = t
    end
    t[name] = value
end

local function get_buffer_filetype(bufnr)
    local buf = get_buffer(bufnr)
    return options.get("filetype", nil, buf, true) or ""
end

local function compute_root_end(bufnr)
    local buf = get_buffer(bufnr)
    local line_count = buf:line_count(false)
    if line_count < 1 then
        return 0, 0
    end
    local last = buf:get_line(line_count, false) or ""
    return line_count - 1, #last
end

local function register_backend(lang, backend)
    backend_by_lang[tostring(lang or "")] = backend
end

local function backend_for_lang(lang)
    return backend_by_lang[lang] or backend_by_lang["*"]
end

local function has_explicit_backend(lang)
    lang = tostring(lang or "")
    return lang ~= "" and backend_by_lang[lang] ~= nil
end

local function has_registered_language(lang)
    lang = tostring(lang or "")
    return lang ~= "" and filetypes_by_lang[lang] ~= nil
end

local function parser_creation_error(bufnr, lang)
    return string.format('Parser could not be created for buffer %s and language "%s"', bufnr, lang)
end

local language = {}

local lang_by_filetype = {
    lua = "lua",
    vim = "vim",
    vimscript = "vim",
    help = "vimdoc",
    vimdoc = "vimdoc",
    query = "query",
}

filetypes_by_lang = {}

local function register_mapping(lang, filetype)
    if type(lang) ~= "string" or lang == "" then
        return
    end
    if type(filetype) ~= "string" or filetype == "" then
        return
    end

    lang_by_filetype[filetype] = lang

    local list = filetypes_by_lang[lang]
    if not list then
        list = {}
        filetypes_by_lang[lang] = list
    end

    for i = 1, #list do
        if list[i] == filetype then
            return
        end
    end

    list[#list + 1] = filetype
end

for filetype, lang in pairs(lang_by_filetype) do
    register_mapping(lang, filetype)
end

function language.register(lang, filetype)
    if type(filetype) == "table" then
        for i = 1, #filetype do
            register_mapping(lang, filetype[i])
        end
        return
    end
    register_mapping(lang, filetype)
end

function language.get_lang(filetype)
    local ft = tostring(filetype or "")
    if ft == "" then
        return ""
    end
    return lang_by_filetype[ft] or ft
end

function language.get_filetypes(lang)
    local name = tostring(lang or "")
    local list = filetypes_by_lang[name]
    if list then
        return copy_list(list)
    end
    if name ~= "" then
        return { name }
    end
    return {}
end

function language.add(lang, _)
    local name = tostring(lang or "")
    if name == "" then
        return false
    end
    if not filetypes_by_lang[name] then
        register_mapping(name, name)
    end
    return true
end

function language.require_language(lang, opts)
    return language.add(lang, opts)
end

function language.inspect(lang)
    local name = tostring(lang or "")
    return {
        lang = name,
        filetypes = language.get_filetypes(name),
        abi_version = 0,
        state = backend_by_lang[name] and "ready" or "compat",
    }
end

local function make_set(items)
    local s = {}
    for i = 1, #items do
        s[items[i]] = true
    end
    return s
end

local LUA_KEYWORDS = make_set({
    "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if", "in", "local",
    "not", "or", "repeat", "return", "then", "until", "while",
})

local LUA_BUILTIN_FUNCTIONS = make_set({
    "assert", "collectgarbage", "dofile", "error", "getfenv", "getmetatable", "ipairs", "load", "loadfile",
    "loadstring", "module", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawlen", "rawset",
    "require", "select", "setfenv", "setmetatable", "tonumber", "tostring", "type", "unpack", "xpcall",
    "__add", "__band", "__bnot", "__bor", "__bxor", "__call", "__concat", "__div", "__eq", "__gc",
    "__idiv", "__index", "__le", "__len", "__lt", "__metatable", "__mod", "__mul", "__name",
    "__newindex", "__pairs", "__pow", "__shl", "__shr", "__sub", "__tostring", "__unm",
})

local LUA_MODULE_BUILTINS = make_set({
    "_G", "debug", "io", "jit", "math", "os", "package", "string", "table", "utf8",
})

local LUA_OPERATOR_CHARS = make_set({
    "+", "-", "*", "/", "%", "^", "#", "=", "<", ">", "&", "~", "|",
})

local function long_bracket_open(line, idx)
    if line:sub(idx, idx) ~= "[" then
        return nil
    end

    local j = idx + 1
    while line:sub(j, j) == "=" do
        j = j + 1
    end

    if line:sub(j, j) ~= "[" then
        return nil
    end

    return (j - idx - 1), (j + 1)
end

local function long_bracket_close(line, idx, eq)
    if line:sub(idx, idx) ~= "]" then
        return nil
    end

    local j = idx + 1
    for _ = 1, eq do
        if line:sub(j, j) ~= "=" then
            return nil
        end
        j = j + 1
    end

    if line:sub(j, j) ~= "]" then
        return nil
    end

    return j
end

local function capture_priority(name)
    if name == "string.escape" then
        return 130
    end
    if name == "comment.documentation" then
        return 120
    end
    if name == "function.builtin" or name == "function.method.call" or name == "function.call" then
        return 120
    end
    if name == "function" or name == "function.method" then
        return 115
    end
    if name:sub(1, 8) == "keyword." or name == "keyword" then
        return 110
    end
    if name == "comment" or name:sub(1, 8) == "comment." then
        return 110
    end
    if name == "number" or name == "boolean" then
        return 108
    end
    if name == "string" then
        return 105
    end
    if name == "variable.parameter" or name == "variable.parameter.builtin" then
        return 106
    end
    return 100
end

local function add_capture(doc, row0, start_col, end_col, capture, text, metadata)
    if end_col <= start_col then
        return
    end

    local capture_ids = doc.capture_ids
    local capture_names = doc.capture_names

    local cid = capture_ids[capture]
    if not cid then
        cid = #capture_names + 1
        capture_ids[capture] = cid
        capture_names[cid] = capture
    end

    local line = doc.captures_by_line[row0]
    if not line then
        line = {}
        doc.captures_by_line[row0] = line
    end

    line[#line + 1] = {
        start_col = start_col,
        end_col = end_col,
        capture = capture,
        id = cid,
        metadata = metadata or {},
        priority = capture_priority(capture),
        text = text,
        row = row0,
    }
end

local function add_token(doc, row0, start_col, end_col, text, kind)
    local tok = {
        row = row0,
        start_col = start_col,
        end_col = end_col,
        text = text,
        kind = kind,
        capture = nil,
        _sig_index = nil,
        _decl_name = false,
    }
    doc.tokens[#doc.tokens + 1] = tok
    return tok
end

local function is_word_start(ch)
    return ch ~= "" and ch:match("[%a_]") ~= nil
end

local function is_word(ch)
    return ch ~= "" and ch:match("[%w_]") ~= nil
end

local function token_is_symbol(tok, s)
    return tok and tok.text == s
end

local function classify_lua_identifier(tok)
    local text = tok.text

    if text == "true" or text == "false" then
        return "boolean"
    end

    if text == "nil" then
        return "constant.builtin"
    end

    if text == "coroutine" then
        return "keyword.coroutine"
    end

    if text == "_VERSION" then
        return "constant.builtin"
    end

    if text == "self" then
        return "variable.builtin"
    end

    if LUA_MODULE_BUILTINS[text] then
        return "module.builtin"
    end

    if text:match("^[A-Z][A-Z_0-9]*$") then
        return "constant"
    end

    return nil
end

local function parse_lua_backend(bufnr, lang)
    local buf = get_buffer(bufnr)
    local lines = buf:lines_ref(true)

    local doc = {
        lang = lang,
        tokens = {},
        captures_by_line = {},
        capture_ids = {},
        capture_names = {},
    }

    local long_state = nil

    for row1 = 1, #lines do
        local line = lines[row1] or ""
        local row0 = row1 - 1
        local line_len = #line

        local i = 1

        if long_state then
            local close_end = nil
            while i <= line_len do
                local got = long_bracket_close(line, i, long_state.eq)
                if got then
                    close_end = got
                    break
                end
                i = i + 1
            end

            if close_end then
                add_capture(doc, row0, 0, close_end, long_state.capture, line:sub(1, close_end), long_state.metadata)
                i = close_end + 1
                long_state = nil
            else
                add_capture(doc, row0, 0, line_len, long_state.capture, line, long_state.metadata)
                goto continue_line
            end
        end

        while i <= line_len do
            local ch = line:sub(i, i)
            local next2 = line:sub(i, i + 1)
            local next3 = line:sub(i, i + 2)

            if next2 == "--" then
                local comment_capture = "comment"
                local comment_text = line:sub(i)
                if comment_text:match("^%-%-%-") or comment_text:match("^%-%-%s?@") then
                    comment_capture = "comment.documentation"
                end

                local eq, content_start = long_bracket_open(line, i + 2)
                if eq then
                    local close_end = nil
                    local j = content_start
                    while j <= line_len do
                        local got = long_bracket_close(line, j, eq)
                        if got then
                            close_end = got
                            break
                        end
                        j = j + 1
                    end

                    if close_end then
                        add_capture(
                            doc,
                            row0,
                            i - 1,
                            close_end,
                            comment_capture,
                            line:sub(i, close_end),
                            { spell = true }
                        )
                        i = close_end + 1
                    else
                        add_capture(doc, row0, i - 1, line_len, comment_capture, line:sub(i), { spell = true })
                        long_state = {
                            capture = comment_capture,
                            eq = eq,
                            metadata = { spell = true },
                        }
                        goto continue_line
                    end
                else
                    add_capture(doc, row0, i - 1, line_len, comment_capture, line:sub(i), { spell = true })
                    break
                end
            elseif ch == "\"" or ch == "'" then
                local quote = ch
                local j = i + 1
                local closed = false

                while j <= line_len do
                    local c = line:sub(j, j)
                    if c == "\\" then
                        local esc_end = math.min(j + 1, line_len)
                        add_capture(doc, row0, j - 1, esc_end, "string.escape", line:sub(j, esc_end))
                        j = j + 2
                    elseif c == quote then
                        closed = true
                        j = j + 1
                        break
                    else
                        j = j + 1
                    end
                end

                local end_col = closed and (j - 1) or line_len
                add_capture(doc, row0, i - 1, end_col, "string", line:sub(i, math.max(i, end_col)))
                i = closed and j or (line_len + 1)
            else
                local eq, content_start = long_bracket_open(line, i)
                if eq then
                    local close_end = nil
                    local j = content_start
                    while j <= line_len do
                        local got = long_bracket_close(line, j, eq)
                        if got then
                            close_end = got
                            break
                        end
                        j = j + 1
                    end

                    if close_end then
                        add_capture(doc, row0, i - 1, close_end, "string", line:sub(i, close_end))
                        i = close_end + 1
                    else
                        add_capture(doc, row0, i - 1, line_len, "string", line:sub(i))
                        long_state = {
                            capture = "string",
                            eq = eq,
                            metadata = {},
                        }
                        goto continue_line
                    end
                elseif is_word_start(ch) then
                    local j = i + 1
                    while is_word(line:sub(j, j)) do
                        j = j + 1
                    end

                    local text = line:sub(i, j - 1)
                    local tok = add_token(doc, row0, i - 1, j - 1, text, "identifier")

                    if LUA_KEYWORDS[text] then
                        if text == "return" then
                            tok.capture = "keyword.return"
                        elseif text == "function" then
                            tok.capture = "keyword.function"
                        elseif text == "if" or text == "elseif" or text == "else" or text == "then" then
                            tok.capture = "keyword.conditional"
                        elseif
                            text == "for"
                            or text == "while"
                            or text == "repeat"
                            or text == "until"
                            or text == "do"
                        then
                            tok.capture = "keyword.repeat"
                        elseif text == "and" or text == "or" or text == "not" then
                            tok.capture = "keyword.operator"
                        else
                            tok.capture = "keyword"
                        end
                        add_capture(doc, row0, tok.start_col, tok.end_col, tok.capture, text)
                    else
                        local special_capture = classify_lua_identifier(tok)
                        if special_capture then
                            tok.capture = special_capture
                            add_capture(doc, row0, tok.start_col, tok.end_col, special_capture, text)
                        end
                    end

                    i = j
                elseif ch:match("%d") then
                    local j = i + 1
                    while j <= line_len do
                        local c = line:sub(j, j)
                        local prev = line:sub(j - 1, j - 1)
                        if c:match("[%w_]") or c == "." then
                            j = j + 1
                        elseif
                            (c == "+" or c == "-")
                            and (prev == "e" or prev == "E" or prev == "p" or prev == "P")
                        then
                            j = j + 1
                        else
                            break
                        end
                    end

                    local text = line:sub(i, j - 1)
                    local tok = add_token(doc, row0, i - 1, j - 1, text, "number")
                    tok.capture = "number"
                    add_capture(doc, row0, tok.start_col, tok.end_col, "number", text)
                    i = j
                elseif next3 == "..." then
                    local tok = add_token(doc, row0, i - 1, i + 2, "...", "symbol")
                    tok.capture = "operator"
                    add_capture(doc, row0, tok.start_col, tok.end_col, "operator", tok.text)
                    i = i + 3
                elseif next2 == "::" or next2 == "==" or next2 == "~=" or next2 == "<=" or next2 == ">="
                    or next2 == "<<" or next2 == ">>" or next2 == "//" or next2 == ".." then
                    local text = next2
                    local tok = add_token(doc, row0, i - 1, i + 1, text, "symbol")

                    if text == "::" then
                        tok.capture = "punctuation.delimiter"
                    elseif text == ".." then
                        tok.capture = "operator"
                    else
                        tok.capture = "operator"
                    end

                    add_capture(doc, row0, tok.start_col, tok.end_col, tok.capture, tok.text)
                    i = i + 2
                elseif ch == ";" or ch == ":" or ch == "," or ch == "." then
                    local tok = add_token(doc, row0, i - 1, i, ch, "symbol")
                    tok.capture = "punctuation.delimiter"
                    add_capture(doc, row0, tok.start_col, tok.end_col, tok.capture, ch)
                    i = i + 1
                elseif ch == "(" or ch == ")" or ch == "[" or ch == "]" or ch == "{" or ch == "}" then
                    local tok = add_token(doc, row0, i - 1, i, ch, "symbol")
                    tok.capture = "punctuation.bracket"
                    add_capture(doc, row0, tok.start_col, tok.end_col, tok.capture, ch)
                    i = i + 1
                elseif LUA_OPERATOR_CHARS[ch] then
                    local tok = add_token(doc, row0, i - 1, i, ch, "symbol")
                    tok.capture = "operator"
                    add_capture(doc, row0, tok.start_col, tok.end_col, tok.capture, ch)
                    i = i + 1
                else
                    i = i + 1
                end
            end
        end

        ::continue_line::
    end

    local sig = {}
    for i = 1, #doc.tokens do
        local tok = doc.tokens[i]
        if tok.kind ~= "comment" then
            tok._sig_index = #sig + 1
            sig[#sig + 1] = tok
        end
    end

    -- Mark function declaration name chain between `function` and `(`.
    local decl_mode = false
    for i = 1, #sig do
        local tok = sig[i]
        if tok.text == "function" then
            decl_mode = true
        elseif decl_mode then
            if tok.text == "(" then
                decl_mode = false
            elseif tok.kind == "identifier" then
                tok._decl_name = true
            end
        end
    end

    -- Mark function parameters.
    local awaiting_params = false
    local param_depth = 0
    for i = 1, #sig do
        local tok = sig[i]
        if param_depth > 0 then
            if tok.text == "(" then
                param_depth = param_depth + 1
            elseif tok.text == ")" then
                param_depth = param_depth - 1
            elseif param_depth == 1 then
                if tok.kind == "identifier" then
                    tok.capture = "variable.parameter"
                elseif tok.text == "..." then
                    tok.capture = "variable.parameter.builtin"
                end
            end
        else
            if tok.text == "function" then
                awaiting_params = true
            elseif awaiting_params and tok.text == "(" then
                param_depth = 1
                awaiting_params = false
            end
        end
    end

    for i = 1, #sig do
        local tok = sig[i]
        if tok.kind == "identifier" then
            local prev = sig[i - 1]
            local next = sig[i + 1]
            local next2 = sig[i + 2]

            local cap = tok.capture or classify_lua_identifier(tok)

            if token_is_symbol(prev, "goto") then
                cap = "label"
            elseif token_is_symbol(prev, "::") and token_is_symbol(next, "::") then
                cap = "label"
            elseif tok._decl_name then
                if token_is_symbol(prev, ":") then
                    cap = "function.method"
                else
                    cap = "function"
                end
            elseif token_is_symbol(next, "(") then
                if LUA_BUILTIN_FUNCTIONS[tok.text] then
                    cap = "function.builtin"
                elseif token_is_symbol(prev, ":") then
                    cap = "function.method.call"
                else
                    cap = "function.call"
                end
            elseif token_is_symbol(prev, ".") then
                cap = "variable.member"
            elseif token_is_symbol(prev, ":") then
                cap = "function.method"
            elseif token_is_symbol(next, "=") and token_is_symbol(next2, "function") then
                cap = "function"
            elseif token_is_symbol(next, "=") and (token_is_symbol(prev, "{") or token_is_symbol(prev, ",")) then
                cap = "property"
            end

            if not cap then
                cap = "variable"
            end

            tok.capture = cap
            add_capture(doc, tok.row, tok.start_col, tok.end_col, cap, tok.text)
        elseif tok.text == "..." and tok.capture == "variable.parameter.builtin" then
            add_capture(doc, tok.row, tok.start_col, tok.end_col, tok.capture, tok.text)
        end
    end

    for _, spans in pairs(doc.captures_by_line) do
        table.sort(spans, function(a, b)
            if a.priority ~= b.priority then
                return a.priority < b.priority
            end
            if a.start_col ~= b.start_col then
                return a.start_col < b.start_col
            end
            return a.end_col < b.end_col
        end)
    end

    local erow, ecol = compute_root_end(bufnr)
    doc.root_end_row = erow
    doc.root_end_col = ecol
    return doc
end

register_backend("*", {
    parse = function(bufnr, lang)
        local erow, ecol = compute_root_end(bufnr)
        return {
            lang = lang,
            tokens = {},
            captures_by_line = {},
            capture_ids = {},
            capture_names = {},
            root_end_row = erow,
            root_end_col = ecol,
        }
    end,
})

register_backend("lua", {
    parse = parse_lua_backend,
})

local FakeNode = {}
FakeNode.__index = FakeNode

function FakeNode:range(include_bytes)
    local srow = self._range[1]
    local scol = self._range[2]
    local erow = self._range[3]
    local ecol = self._range[4]
    if include_bytes then
        return srow, scol, erow, ecol, 0, 0
    end
    return srow, scol, erow, ecol
end

function FakeNode:start()
    return self._range[1], self._range[2], 0
end

function FakeNode:end_()
    return self._range[3], self._range[4], 0
end

function FakeNode:type()
    return self._type or "document"
end

function FakeNode:id()
    return self._id
end

function FakeNode:named()
    return true
end

function FakeNode:missing()
    return false
end

function FakeNode:extra()
    return false
end

function FakeNode:has_error()
    return false
end

function FakeNode:has_changes()
    return false
end

function FakeNode:sexpr()
    return "(" .. (self._type or "document") .. ")"
end

function FakeNode:parent()
    return self._parent or self
end

function FakeNode:child()
    return nil
end

function FakeNode:child_count()
    return 0
end

function FakeNode:named_child()
    return nil
end

function FakeNode:named_child_count()
    return 0
end

function FakeNode:named_children()
    return {}
end

function FakeNode:field()
    return {}
end

function FakeNode:iter_children()
    return function()
        return nil
    end
end

function FakeNode:child_with_descendant()
    return self
end

function FakeNode:next_sibling()
    return nil
end

function FakeNode:prev_sibling()
    return nil
end

function FakeNode:next_named_sibling()
    return nil
end

function FakeNode:prev_named_sibling()
    return nil
end

function FakeNode:descendant_for_range()
    return self
end

function FakeNode:named_descendant_for_range()
    return self
end

function FakeNode:equal(other)
    return rawequal(self, other)
end

function FakeNode:tree()
    return self._tree
end

local FakeTree = {}
FakeTree.__index = FakeTree

function FakeTree:new(bufnr, lang, doc)
    local erow = doc and doc.root_end_row or 0
    local ecol = doc and doc.root_end_col or 0

    local root = setmetatable({
        _id = 1,
        _range = { 0, 0, erow, ecol },
        _lang = lang,
        _bufnr = bufnr,
        _type = "document",
    }, FakeNode)

    local tree = setmetatable({
        _bufnr = bufnr,
        _lang = lang,
        _root = root,
    }, FakeTree)

    root._tree = tree
    root._parent = root
    return tree
end

function FakeTree:root()
    return self._root
end

function FakeTree:copy()
    return self
end

function FakeTree:included_ranges()
    return {}
end

local FakeParser = {}
FakeParser.__index = FakeParser

function FakeParser:new(bufnr, lang)
    return setmetatable({
        _bufnr = bufnr,
        _lang = lang,
        _backend = backend_for_lang(lang),
        _doc = nil,
        _tree = FakeTree:new(bufnr, lang, nil),
    }, FakeParser)
end

function FakeParser:_reparse()
    self._doc = self._backend.parse(self._bufnr, self._lang)
    self._tree = FakeTree:new(self._bufnr, self._lang, self._doc)
end

function FakeParser:get_doc()
    if not self._doc then
        self:_reparse()
    end
    return self._doc
end

function FakeParser:parse(range, on_parse)
    local cb = nil
    if type(range) == "function" then
        cb = range
    elseif type(on_parse) == "function" then
        cb = on_parse
    end

    self:_reparse()

    local trees = { self._tree }
    if cb then
        cb(nil, trees)
    end

    return trees
end

function FakeParser:lang()
    return self._lang
end

function FakeParser:source()
    return self._bufnr
end

function FakeParser:for_each_tree(fn)
    if type(fn) == "function" then
        if not self._doc then
            self:_reparse()
        end
        fn(self._tree, self)
    end
end

function FakeParser:register_cbs()
    return true
end

function FakeParser:tree_for_range()
    if not self._doc then
        self:_reparse()
    end
    return self._tree
end

function FakeParser:node_for_range()
    return self:tree_for_range():root()
end

function FakeParser:named_node_for_range()
    return self:tree_for_range():root()
end

function FakeParser:destroy()
    parser_by_buf[self._bufnr] = nil
end

local QueryMatch = {}
QueryMatch.__index = QueryMatch

function QueryMatch:new(match_id, pattern_id, captures)
    return setmetatable({
        _match_id = match_id,
        _pattern_id = pattern_id,
        _captures = captures,
    }, QueryMatch)
end

function QueryMatch:info()
    return self._match_id, self._pattern_id
end

function QueryMatch:captures()
    return self._captures
end

local Query = {}
Query.__index = Query

local function extract_captures(query_text)
    local captures = {}
    local seen = {}
    for capture in tostring(query_text or ""):gmatch("@([%w%._%-]+)") do
        if not seen[capture] then
            captures[#captures + 1] = capture
            seen[capture] = true
        end
    end
    return captures
end

function Query:new(lang, query_text)
    return setmetatable({
        lang = lang,
        query = tostring(query_text or ""),
        captures = extract_captures(query_text),
        info = {
            captures = {},
            patterns = {},
        },
    }, Query)
end

local function query_capture_id(self, capture)
    for i = 1, #self.captures do
        if self.captures[i] == capture then
            return i
        end
    end

    self.captures[#self.captures + 1] = capture
    return #self.captures
end

local function doc_for_query_source(source, lang)
    if type(source) ~= "number" then
        return nil, nil, nil
    end

    local parser = M.get_parser(source, lang, { error = false })
    if not parser then
        return nil, nil, nil
    end

    local tree = parser:parse()[1]
    local doc = parser:get_doc()
    return doc, tree, parser
end

local function spans_in_range(doc, start_row, stop_row)
    local out = {}
    local sr = tonumber(start_row) or 0
    local er = tonumber(stop_row or (sr + 1)) or (sr + 1)

    for row = sr, er - 1 do
        local spans = doc.captures_by_line[row]
        if spans then
            for i = 1, #spans do
                out[#out + 1] = spans[i]
            end
        end
    end

    return out
end

local function span_to_node(tree, span, next_id)
    return setmetatable({
        _id = next_id,
        _range = { span.row, span.start_col, span.row, span.end_col },
        _lang = tree._lang,
        _bufnr = tree._bufnr,
        _tree = tree,
        _parent = tree:root(),
        _type = "token",
        _text = span.text,
    }, FakeNode)
end

function Query:iter_captures(_, source, start, stop)
    local doc, tree = doc_for_query_source(source, self.lang)
    if not doc then
        return function()
            return nil
        end
    end

    local spans = spans_in_range(doc, start, stop)
    local idx = 0

    return function()
        idx = idx + 1
        local span = spans[idx]
        if not span then
            return nil
        end

        local cid = query_capture_id(self, span.capture)
        local node = span_to_node(tree, span, idx + 1000)
        local metadata = span.metadata or {}
        local captures = { [cid] = { node } }
        local match = QueryMatch:new(idx, 1, captures)

        return cid, node, metadata, match, tree
    end
end

function Query:iter_matches(_, source, start, stop)
    local doc, tree = doc_for_query_source(source, self.lang)
    if not doc then
        return function()
            return nil
        end
    end

    local spans = spans_in_range(doc, start, stop)
    local idx = 0

    return function()
        idx = idx + 1
        local span = spans[idx]
        if not span then
            return nil
        end

        local cid = query_capture_id(self, span.capture)
        local node = span_to_node(tree, span, idx + 2000)
        local metadata = { [cid] = span.metadata or {} }
        local match = { [cid] = { node } }

        return 1, match, metadata, tree
    end
end

local predicates = {}
local directives = {}

local query = {}

local function read_file(path)
    local h = fs.open(path, "r")
    if not h then
        return nil
    end
    local text = h.readAll() or ""
    h.close()
    return text
end

local function query_paths(lang, query_name)
    if lang == "" or query_name == "" then
        return {}
    end

    local pattern = ("queries/%s/%s.scm"):format(lang, query_name)
    return api.nvim_get_runtime_file(pattern, true) or {}
end

function query.parse(lang, query_text)
    local name = tostring(lang or "")
    if name ~= "" then
        language.add(name)
    end
    return Query:new(name, query_text)
end

function query.get(lang, query_name)
    local lname = tostring(lang or "")
    local qname = tostring(query_name or "")

    local by_lang = query_overrides[lname]
    if by_lang and by_lang[qname] ~= nil then
        return query.parse(lname, by_lang[qname])
    end

    local files = query_paths(lname, qname)
    if #files == 0 then
        return nil
    end

    local chunks = {}
    for i = 1, #files do
        local text = read_file(files[i])
        if text then
            chunks[#chunks + 1] = text
        end
    end

    if #chunks == 0 then
        return nil
    end

    return query.parse(lname, table.concat(chunks, "\n"))
end

function query.set(lang, query_name, text)
    lang = tostring(lang or "")
    query_name = tostring(query_name or "")
    if lang == "" or query_name == "" then
        return false
    end

    local by_lang = query_overrides[lang]
    if not by_lang then
        by_lang = {}
        query_overrides[lang] = by_lang
    end

    by_lang[query_name] = tostring(text or "")
    return true
end

function query.get_files(lang, query_name)
    return copy_list(query_paths(tostring(lang or ""), tostring(query_name or "")))
end

function query.lint()
    return true
end

function query.edit()
    return false
end

function query.omnifunc(findstart)
    if tonumber(findstart or 0) == 1 then
        return 0
    end
    return {}
end

function query.add_predicate(name, handler)
    predicates[tostring(name or "")] = handler
end

function query.add_directive(name, handler)
    directives[tostring(name or "")] = handler
end

function query.list_predicates()
    local out = {}
    for name in pairs(predicates) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

function query.list_directives()
    local out = {}
    for name in pairs(directives) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

local function resolve_capture_hl_group(capture, lang)
    if capture:sub(1, 1) == "_" then
        return nil
    end

    local base = "@" .. capture
    local candidates = {}

    candidates[#candidates + 1] = base .. "." .. lang

    local cur = capture
    while cur and cur ~= "" do
        candidates[#candidates + 1] = "@" .. cur
        local dot = cur:match("^(.+)%.([^.]+)$")
        cur = dot
    end

    local fallback = nil
    if capture:sub(1, 8) == "comment." or capture == "comment" then
        fallback = "Comment"
    elseif capture:sub(1, 7) == "string." or capture == "string" then
        fallback = "String"
    elseif capture == "number" then
        fallback = "Number"
    elseif capture == "boolean" then
        fallback = "Boolean"
    elseif capture:sub(1, 9) == "constant." or capture == "constant" then
        fallback = "Constant"
    elseif capture:sub(1, 9) == "variable." or capture == "variable" or capture == "module" then
        fallback = "Identifier"
    elseif capture:sub(1, 9) == "function." or capture == "function" then
        fallback = "Function"
    elseif capture:sub(1, 8) == "keyword." or capture == "keyword" then
        fallback = "Keyword"
    elseif capture == "operator" then
        fallback = "Operator"
    elseif capture:sub(1, 12) == "punctuation." then
        fallback = "Delimiter"
    elseif capture == "label" then
        fallback = "Label"
    elseif capture == "attribute" then
        fallback = "Macro"
    elseif capture == "constructor" then
        fallback = "Special"
    end

    if fallback then
        candidates[#candidates + 1] = fallback
    end

    for i = 1, #candidates do
        local name = candidates[i]
        if Highlight.HasGroup(name) then
            return name
        end
    end

    return nil
end

local function copy_blit_chars(line, base, normal_fg, normal_bg)
    local len = #line
    local fg_chars = {}
    local bg_chars = {}

    if base and type(base.fg) == "string" and #base.fg == len and type(base.bg) == "string" and #base.bg == len then
        for i = 1, len do
            fg_chars[i] = base.fg:sub(i, i)
            bg_chars[i] = base.bg:sub(i, i)
        end
    else
        for i = 1, len do
            fg_chars[i] = normal_fg
            bg_chars[i] = normal_bg
        end
    end

    return fg_chars, bg_chars
end

local highlighter = {
    active = {},
}

function highlighter.new(parser)
    local bufnr = parser:source()

    local obj = {
        tree = parser,
        _bufnr = bufnr,
        _hl_cache = {},
    }

    function obj:_ensure_doc()
        self.tree:parse()
        return self.tree:get_doc()
    end

    function obj:_resolve_blit_colors(capture, lang)
        local key = lang .. "::" .. capture
        local cached = self._hl_cache[key]
        if cached then
            return cached[1], cached[2]
        end

        local group = resolve_capture_hl_group(capture, lang)
        if not group then
            self._hl_cache[key] = { false, false }
            return false, false
        end

        local hl = Highlight.For(group)
        local fg = hl[1] and colors.toBlit(hl[1]) or false
        local bg = hl[2] and colors.toBlit(hl[2]) or false
        self._hl_cache[key] = { fg, bg }
        return fg, bg
    end

    function obj:build_blits(buffer, first_line, last_line, base)
        local doc = self:_ensure_doc()
        local lang = self.tree:lang()

        local normal = Highlight.For("Normal")
        local normal_fg = colors.toBlit(normal[1])
        local normal_bg = colors.toBlit(normal[2])

        local out = base or {}

        for lnum = first_line, last_line do
            local line = buffer:get_line(lnum, true) or ""
            local spans = doc.captures_by_line[lnum - 1]
            local len = #line

            if spans and len > 0 then
                local entry = out[lnum]
                local fg_chars, bg_chars = copy_blit_chars(line, entry, normal_fg, normal_bg)

                for si = 1, #spans do
                    local span = spans[si]
                    local s = math.max(1, math.min(len, span.start_col + 1))
                    local e = math.max(0, math.min(len, span.end_col))
                    if e >= s then
                        local fg, bg = self:_resolve_blit_colors(span.capture, lang)
                        if fg or bg then
                            for c = s, e do
                                if fg then fg_chars[c] = fg end
                                if bg then bg_chars[c] = bg end
                            end
                        end
                    end
                end

                out[lnum] = {
                    fg = table.concat(fg_chars),
                    bg = table.concat(bg_chars),
                }
            end
        end

        return out
    end

    function obj:captures_at_pos(row0, col0)
        local doc = self:_ensure_doc()
        local spans = doc.captures_by_line[row0]
        if not spans then
            return {}
        end

        local out = {}
        for i = 1, #spans do
            local span = spans[i]
            if col0 >= span.start_col and col0 < span.end_col then
                out[#out + 1] = {
                    capture = span.capture,
                    lang = self.tree:lang(),
                    metadata = span.metadata or {},
                    id = span.id,
                }
            end
        end

        return out
    end

    function obj:destroy()
        highlighter.active[self._bufnr] = nil
        set_buffer_var(self._bufnr, "ts_highlight", nil)
    end

    highlighter.active[bufnr] = obj
    set_buffer_var(bufnr, "ts_highlight", 1)
    return obj
end

local function resolve_lang(bufnr, lang)
    local resolved = tostring(lang or "")
    if resolved ~= "" then
        return resolved
    end

    local filetype = get_buffer_filetype(bufnr)
    resolved = language.get_lang(filetype)
    if resolved == "" then
        resolved = "text"
    end

    return resolved
end

function M.get_parser(bufnr, lang, opts)
    opts = opts or {}
    local should_error = opts.error == nil or opts.error
    bufnr = resolve_bufnr(bufnr)

    local buf = get_buffer(bufnr)
    if not buf then
        if not should_error then
            return nil
        end
        error(("Invalid buffer id: %s"):format(tostring(bufnr)), 2)
    end

    local resolved_lang = resolve_lang(bufnr, lang)
    if not has_explicit_backend(resolved_lang) and not has_registered_language(resolved_lang) then
        local err_msg = parser_creation_error(bufnr, resolved_lang)
        if not should_error then
            return nil, err_msg
        end
        error(err_msg, 2)
    end

    local parser = parser_by_buf[bufnr]
    if parser and parser:lang() == resolved_lang then
        return parser
    end

    parser = FakeParser:new(bufnr, resolved_lang)
    parser_by_buf[bufnr] = parser
    return parser
end

function M.start(bufnr, lang)
    bufnr = resolve_bufnr(bufnr)

    local resolved_lang = resolve_lang(bufnr, lang)
    if not has_explicit_backend(resolved_lang) then
        if has_registered_language(resolved_lang) then
            return nil
        end
        error(parser_creation_error(bufnr, resolved_lang), 2)
    end

    if highlighter.active[bufnr] then
        highlighter.active[bufnr]:destroy()
    end

    local parser = M.get_parser(bufnr, resolved_lang, { error = false })
    if not parser then
        return nil
    end

    highlighter.new(parser)
    return nil
end

function M.stop(bufnr)
    bufnr = resolve_bufnr(bufnr)

    if highlighter.active[bufnr] then
        highlighter.active[bufnr]:destroy()
    end

    parser_by_buf[bufnr] = nil
end

function M.foldexpr()
    return "0"
end

function M.inspect_tree()
    return nil
end

function M.get_captures_at_pos(bufnr, row, col)
    bufnr = resolve_bufnr(bufnr)

    local active = highlighter.active[bufnr]
    if not active then
        return {}
    end

    return active:captures_at_pos(tonumber(row) or 0, tonumber(col) or 0)
end

function M.get_captures_at_cursor(winnr)
    local win = winnr or 0
    local bufnr = api.nvim_win_get_buf(win)
    local cursor = api.nvim_win_get_cursor(win)

    local row = (cursor[1] or 1) - 1
    local col = cursor[2] or 0
    local data = M.get_captures_at_pos(bufnr, row, col)

    local out = {}
    for i = 1, #data do
        out[#out + 1] = data[i].capture
    end
    return out
end

local function node_or_range_to_4(value)
    if type(value) == "table" and type(value.range) == "function" then
        local srow, scol, erow, ecol = value:range()
        return srow, scol, erow, ecol
    end

    if type(value) == "table" and #value >= 4 then
        return value[1], value[2], value[3], value[4]
    end

    return nil
end

function M.get_node_text(node, source)
    if node and type(node) == "table" and node._text ~= nil then
        return tostring(node._text)
    end

    if type(source) == "number" and node and type(node.range) == "function" then
        local srow, scol, erow, ecol = node:range()
        local buf = get_buffer(source)
        if not buf then
            return ""
        end

        if srow == erow then
            local line = buf:get_line(srow + 1, true) or ""
            local s = math.max(1, scol + 1)
            local e = math.max(0, ecol)
            return line:sub(s, e)
        end

        local parts = {}
        for row = srow, erow do
            local line = buf:get_line(row + 1, true) or ""
            if row == srow then
                parts[#parts + 1] = line:sub(scol + 1)
            elseif row == erow then
                parts[#parts + 1] = line:sub(1, ecol)
            else
                parts[#parts + 1] = line
            end
        end
        return table.concat(parts, "\n")
    end

    return ""
end

function M.get_range(node)
    if node and type(node.range) == "function" then
        local srow, scol, erow, ecol = node:range()
        return { srow, scol, erow, ecol }
    end
    return { 0, 0, 0, 0 }
end

function M.node_contains(node, node_or_range)
    local nsr, nsc, ner, nec = node_or_range_to_4(node)
    local tsr, tsc, ter, tec = node_or_range_to_4(node_or_range)
    if not nsr or not tsr then
        return false
    end
    if tsr < nsr or ter > ner then
        return false
    end
    if tsr == nsr and tsc < nsc then
        return false
    end
    if ter == ner and tec > nec then
        return false
    end
    return true
end

function M.get_node(opts)
    opts = opts or {}
    local bufnr = resolve_bufnr(opts.bufnr)
    local parser = M.get_parser(bufnr, opts.lang, { error = false })
    if not parser then
        return nil
    end
    return parser:parse()[1]:root()
end

function M._apply_highlight_blits(buffer, first_line, last_line, base_blits)
    local bufnr = buffer and buffer.bufnr
    if not bufnr then
        return base_blits
    end

    local active = highlighter.active[bufnr]
    if not active then
        return base_blits
    end

    return active:build_blits(buffer, first_line, last_line, base_blits)
end

function M._ts_get_language_version()
    return LANGUAGE_VERSION
end

function M._ts_get_minimum_language_version()
    return MINIMUM_LANGUAGE_VERSION
end

M.language = language
M.query = query
M.highlighter = highlighter
M.register_backend = register_backend

M.language_version = 1
M.minimum_language_version = 1

package.loaded["vim.treesitter"] = M
package.loaded["vim.treesitter.language"] = language
package.loaded["vim.treesitter.query"] = query
package.loaded["vim.treesitter.highlighter"] = highlighter

return M
