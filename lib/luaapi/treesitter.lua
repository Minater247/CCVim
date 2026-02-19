-- Minimal Treesitter compatibility layer.
-- This is intentionally narrow: it prevents runtime ftplugin failures and
-- provides an API surface that can be incrementally replaced by a real
-- parser/query backend.

local M = {}

local api = loadModule("vim.lib.luaapi.api")
local options = loadModule("vim.lib.options")
local scopes = loadModule("vim.lib.luaapi.scopes")
local package = loadModule("vim.lib.luaapi.package")

local parser_by_buf = {}
local query_overrides = {}

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
    return buffers and buffers[bufnr] or nil
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
    if not buf then
        return ""
    end
    return options.get("filetype", nil, buf, true) or ""
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

local filetypes_by_lang = {}

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
        state = "compat",
    }
end

local function compute_root_end(bufnr)
    local buf = get_buffer(bufnr)
    if not buf then
        return 0, 0
    end
    local line_count = buf:line_count(false)
    if line_count < 1 then
        return 0, 0
    end
    local last = buf:get_line(line_count, false) or ""
    return line_count - 1, #last
end

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
    return "document"
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
    return "(document)"
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

function FakeTree:new(bufnr, lang)
    local erow, ecol = compute_root_end(bufnr)
    local root = setmetatable({
        _id = 1,
        _range = { 0, 0, erow, ecol },
        _lang = lang,
        _bufnr = bufnr,
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
        _tree = FakeTree:new(bufnr, lang),
    }, FakeParser)
end

function FakeParser:parse(range, on_parse)
    local cb = nil
    if type(range) == "function" then
        cb = range
    elseif type(on_parse) == "function" then
        cb = on_parse
    end

    self._tree = FakeTree:new(self._bufnr, self._lang)
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
        fn(self._tree, self)
    end
end

function FakeParser:register_cbs()
    return true
end

function FakeParser:tree_for_range()
    return self._tree
end

function FakeParser:node_for_range()
    return self._tree:root()
end

function FakeParser:named_node_for_range()
    return self._tree:root()
end

function FakeParser:destroy()
    parser_by_buf[self._bufnr] = nil
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

function Query:iter_matches()
    return function()
        return nil
    end
end

function Query:iter_captures()
    return function()
        return nil
    end
end

local predicates = {}
local directives = {}

local query = {}

function query.parse(lang, query_text)
    local name = tostring(lang or "")
    if name ~= "" then
        language.add(name)
    end
    return Query:new(name, query_text)
end

function query.get(lang, query_name)
    local by_lang = query_overrides[tostring(lang or "")]
    if not by_lang then
        return nil
    end
    local text = by_lang[tostring(query_name or "")]
    if text == nil then
        return nil
    end
    return query.parse(lang, text)
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

function query.get_files()
    return {}
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

local highlighter = {
    active = {},
}

function highlighter.new(parser)
    if not parser then
        return nil
    end
    local bufnr = parser:source()
    if not bufnr then
        return nil
    end

    local obj = {
        tree = parser,
        _bufnr = bufnr,
    }

    function obj:destroy()
        highlighter.active[self._bufnr] = nil
        set_buffer_var(self._bufnr, "ts_highlight", nil)
    end

    highlighter.active[bufnr] = obj
    -- TODO: this needs to be set to 1 once treesitter is set up more reliably
    set_buffer_var(bufnr, "ts_highlight", nil)
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
    bufnr = resolve_bufnr(bufnr)
    local buf = get_buffer(bufnr)
    if not buf then
        if opts.error == false then
            return nil
        end
        error(("Invalid buffer id: %s"):format(tostring(bufnr)), 2)
    end

    local resolved_lang = resolve_lang(bufnr, lang)
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
    local parser = M.get_parser(bufnr, lang, { error = false })
    if not parser then
        return nil
    end
    if highlighter.active[bufnr] then
        highlighter.active[bufnr]:destroy()
    end
    return highlighter.new(parser)
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

function M.get_captures_at_pos()
    return {}
end

function M.get_captures_at_cursor()
    return {}
end

function M.get_node_text(node)
    if node and type(node) == "table" and node._text ~= nil then
        return tostring(node._text)
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

local function unpack_node_or_range(value)
    if type(value) == "table" and type(value.range) == "function" then
        local srow, scol, erow, ecol = value:range()
        return srow, scol, erow, ecol
    end
    if type(value) == "table" and #value >= 4 then
        return value[1], value[2], value[3], value[4]
    end
    return nil
end

function M.node_contains(node, node_or_range)
    local nsr, nsc, ner, nec = unpack_node_or_range(node)
    local tsr, tsc, ter, tec = unpack_node_or_range(node_or_range)
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

function M.get_node()
    return nil
end

M.language = language
M.query = query
M.highlighter = highlighter

M.language_version = 0
M.minimum_language_version = 0

package.loaded["vim.treesitter"] = M
package.loaded["vim.treesitter.language"] = language
package.loaded["vim.treesitter.query"] = query
package.loaded["vim.treesitter.highlighter"] = highlighter

return M
