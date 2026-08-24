local M = {}

local protocol = require('vim.lsp.protocol')
local methods = protocol.Methods

local function entry(detail, params, kind)
  return { detail = detail, params = params, kind = kind }
end

local function library(name, declarations)
  local out = {}
  for declaration in declarations:gmatch('[^;]+') do
    declaration = declaration:match('^%s*(.-)%s*$')
    local member, raw = declaration:match('^([%w_]+)%((.*)%)$')
    local params = {}
    if member then
      for param in raw:gmatch('[^,]+') do params[#params + 1] = param:match('^%s*(.-)%s*$') end
      out[member] = entry(('%s.%s function'):format(name, member), params)
    else
      out[declaration] = entry(('%s.%s value'):format(name, declaration), nil, 21)
    end
  end
  return out
end

local COMPLETIONS = {
  _G = entry('Global environment', nil, 9), _VERSION = entry('Lua version', nil, 21),
  assert = entry('Assert a condition', { 'value', 'message?' }),
  collectgarbage = entry('Control the garbage collector', { 'option?', 'arg?' }),
  dofile = entry('Execute a Lua file', { 'filename?' }),
  error = entry('Raise a Lua error', { 'message', 'level?' }),
  gcinfo = entry('Return allocated memory in kilobytes', {}),
  getfenv = entry('Get a function environment', { 'function?' }),
  getmetatable = entry('Get a value metatable', { 'object' }),
  ipairs = entry('Iterate an array', { 'table' }),
  load = entry('Load a Lua chunk', { 'chunk', 'chunkname?', 'mode?', 'env?' }),
  loadfile = entry('Load a Lua file', { 'filename?', 'mode?', 'env?' }),
  loadstring = entry('Load a Lua string', { 'string', 'chunkname?' }),
  module = entry('Create or reuse a module table', { 'name', '...' }),
  newproxy = entry('Create a userdata proxy', { 'proxy?' }),
  next = entry('Get the next table key', { 'table', 'index?' }),
  pairs = entry('Iterate a table', { 'table' }),
  pcall = entry('Call a function safely', { 'function', '...' }),
  print = entry('Print values', { '...' }),
  rawequal = entry('Compare without metamethods', { 'a', 'b' }),
  rawget = entry('Read a table without metamethods', { 'table', 'index' }),
  rawset = entry('Write a table without metamethods', { 'table', 'index', 'value' }),
  require = entry('Load a Lua module', { 'module' }),
  select = entry('Select varargs', { 'index', '...' }),
  setfenv = entry('Set a function environment', { 'function', 'environment' }),
  setmetatable = entry('Set a table metatable', { 'table', 'metatable' }),
  tonumber = entry('Convert to number', { 'value', 'base?' }),
  tostring = entry('Convert to string', { 'value' }),
  type = entry('Return a value type', { 'value' }),
  unpack = entry('Return elements from a list', { 'list', 'start?', 'end?' }),
  xpcall = entry('Call a function with an error handler', { 'function', 'message_handler' }),
  arg = entry('Process arguments', nil, 9),
  bit = entry('LuaJIT bit operations', nil, 9),
  coroutine = entry('Lua coroutine library', nil, 9),
  debug = entry('Lua debug library', nil, 9),
  io = entry('Lua I/O library', nil, 9),
  jit = entry('LuaJIT control library', nil, 9),
  lpeg = entry('LPeg pattern library', nil, 9),
  math = entry('Lua math library', nil, 9),
  os = entry('Lua operating-system library', nil, 9),
  package = entry('Lua package library', nil, 9),
  string = entry('Lua string library', nil, 9),
  table = entry('Lua table library', nil, 9),
  vim = entry('Neovim Lua API', nil, 9),
}

local BIT_COMPLETIONS = library('bit', [[
  arshift(value,shift); band(...); bnot(value); bor(...); bswap(value); bxor(...); lshift(value,shift);
  rol(value,shift); ror(value,shift); rshift(value,shift); tobit(value); tohex(value,digits?)
]])
local COROUTINE_COMPLETIONS = library('coroutine', [[
  create(function); isyieldable(); resume(coroutine,...); running(); status(coroutine); wrap(function); yield(...)
]])
local DEBUG_COMPLETIONS = library('debug', [[
  debug(); getfenv(object); gethook(thread?); getinfo(thread?,function,what?); getlocal(thread?,level,index);
  getmetatable(value); getregistry(); getupvalue(function,index); setfenv(object,environment);
  sethook(thread?,hook,mask?,count?); setlocal(thread?,level,index,value); setmetatable(value,table);
  setupvalue(function,index,value); traceback(thread?,message?,level?); upvalueid(function,index);
  upvaluejoin(function1,index1,function2,index2)
]])
local IO_COMPLETIONS = library('io', [[
  close(file?); flush(); input(file?); lines(filename?,...); open(filename,mode?); output(file?);
  popen(program,mode?); read(...); tmpfile(); type(object); write(...)
]])
IO_COMPLETIONS.stdin, IO_COMPLETIONS.stdout, IO_COMPLETIONS.stderr =
  entry('Standard input stream', nil, 6), entry('Standard output stream', nil, 6),
  entry('Standard error stream', nil, 6)
local JIT_COMPLETIONS = library('jit', [[
  attach(callback,event?); flush(function?,recursive?); off(function?,recursive?); on(function?,recursive?);
  security(option?); status(); arch; os; version; version_num; opt
]])
local JIT_OPT_COMPLETIONS = library('jit.opt', 'start(...)')
local LPEG_COMPLETIONS = library('lpeg', [[
  B(pattern); C(pattern); Carg(index); Cb(name); Cc(...); Cf(pattern,function); Cg(pattern,name?);
  Cmt(pattern,function); Cp(); Cs(pattern); Ct(pattern); P(value); R(...); S(string); V(key); locale(table?);
  match(pattern,subject,init?,...); pcode(pattern); ptree(pattern); setmaxstack(max); type(value);
  utfR(first,last); version
]])
local MATH_COMPLETIONS = library('math', [[
  abs(value); acos(value); asin(value); atan(value); atan2(y,x); ceil(value); cos(value); cosh(value);
  deg(radians); exp(value); floor(value); fmod(x,y); frexp(value); ldexp(mantissa,exponent);
  log(value,base?); log10(value); max(...); min(...); modf(value); pow(x,y); rad(degrees);
  random(min?,max?); randomseed(seed); sin(value); sinh(value); sqrt(value); tan(value); tanh(value); huge; pi
]])
local OS_COMPLETIONS = library('os', [[
  clock(); date(format?,time?); difftime(time2,time1); execute(command?); exit(code?,close?); getenv(name);
  remove(filename); rename(oldname,newname); setlocale(locale?,category?); time(table?); tmpname()
]])
local PACKAGE_COMPLETIONS = library('package', [[
  loadlib(library,function); searchpath(name,path,separator?,replacement?); seeall(module);
  config; cpath; loaded; loaders; path; preload
]])
local STRING_COMPLETIONS = library('string', [[
  byte(string,start?,end?); char(...); dump(function,strip?); find(string,pattern,init?,plain?);
  format(format,...); gmatch(string,pattern); gsub(string,pattern,replacement,count?); len(string);
  lower(string); match(string,pattern,init?); rep(string,count,separator?); reverse(string);
  sub(string,start,end?); upper(string)
]])
local TABLE_COMPLETIONS = library('table', [[
  concat(list,separator?,start?,end?); foreach(table,function); foreachi(table,function); getn(table);
  insert(list,position?,value); maxn(table); move(source,first,last,target,destination?);
  remove(list,position?); sort(list,compare?)
]])
TABLE_COMPLETIONS.insert.params = { 'list', 'pos', 'value' }
TABLE_COMPLETIONS.insert.overloads = {
  { 'list', 'pos', 'value' },
  { 'list', 'value' },
}

local VIM_COMPLETIONS = {
  api = entry('Nvim API functions', nil, 9), diagnostic = entry('Diagnostic API', nil, 9),
  fn = entry('Vim functions', nil, 9), keymap = entry('Keymap API', nil, 9),
  lsp = entry('Language Server Protocol API', nil, 9),
  notify = entry('Show a notification', { 'message', 'level?', 'opts?' }),
  schedule = entry('Schedule a callback', { 'callback' }),
  schedule_wrap = entry('Wrap a scheduled callback', { 'callback' }),
  uv = entry('Libuv API', nil, 9),
}

local API_COMPLETIONS = {
  nvim_buf_get_lines = entry('Get buffer lines', { 'buffer', 'start', 'end_', 'strict_indexing' }),
  nvim_buf_set_lines = entry('Set buffer lines', { 'buffer', 'start', 'end_', 'strict_indexing', 'replacement' }),
  nvim_buf_get_name = entry('Get buffer name', { 'buffer' }),
  nvim_buf_set_name = entry('Set buffer name', { 'buffer', 'name' }),
  nvim_create_autocmd = entry('Create an autocommand', { 'event', 'opts' }),
  nvim_create_augroup = entry('Create an autocommand group', { 'name', 'opts' }),
  nvim_create_buf = entry('Create a buffer', { 'listed', 'scratch' }),
  nvim_exec_autocmds = entry('Execute autocommands', { 'event', 'opts' }),
  nvim_feedkeys = entry('Queue input keys', { 'keys', 'mode', 'escape_ks' }),
  nvim_get_current_buf = entry('Get current buffer', {}),
  nvim_get_current_line = entry('Get current line', {}),
  nvim_get_current_win = entry('Get current window', {}),
  nvim_set_current_line = entry('Set current line', { 'line' }),
  nvim_win_get_buf = entry('Get window buffer', { 'window' }),
  nvim_win_get_cursor = entry('Get window cursor', { 'window' }),
  nvim_win_set_cursor = entry('Set window cursor', { 'window', 'position' }),
}

local MEMBER_COMPLETIONS = {
  bit = BIT_COMPLETIONS,
  coroutine = COROUTINE_COMPLETIONS,
  debug = DEBUG_COMPLETIONS,
  io = IO_COMPLETIONS,
  jit = JIT_COMPLETIONS,
  ['jit.opt'] = JIT_OPT_COMPLETIONS,
  lpeg = LPEG_COMPLETIONS,
  math = MATH_COMPLETIONS,
  os = OS_COMPLETIONS,
  package = PACKAGE_COMPLETIONS,
  string = STRING_COMPLETIONS,
  table = TABLE_COMPLETIONS,
  vim = VIM_COMPLETIONS,
  ['vim.api'] = API_COMPLETIONS,
}

local function lines(text)
  local out = {}
  text = tostring(text or '')
  for line in (text .. '\n'):gmatch('(.-)\n') do out[#out + 1] = line end
  return out
end

local function word_at(line, character)
  local before = line:sub(1, character + 1)
  local after = line:sub(character + 2)
  return (before:match('([%a_][%w_]*)$') or '') .. (after:match('^([%w_]*)') or '')
end

local function split_params(raw)
  local out = {}
  for param in tostring(raw or ''):gmatch('[^,]+') do
    param = param:match('^%s*(.-)%s*$')
    if param ~= '' then out[#out + 1] = param end
  end
  return out
end

local function declaration_params(doc_lines, row, tail)
  local text = tail or ''
  local next_row = row + 1
  while not text:find(')', 1, true) and next_row <= #doc_lines do
    text = text .. ' ' .. doc_lines[next_row]
    next_row = next_row + 1
  end
  return split_params(text:match('^(.-)%)') or text)
end

local function analyze(doc_lines)
  local definitions, symbols, identifiers = {}, {}, {}
  local function add(name, row, kind, params)
    local line = doc_lines[row] or ''
    local col = (line:find(name, 1, true) or 1) - 1
    local base = name:match('([%a_][%w_]*)$') or name
    local symbol = {
      name = name, base = base, kind = kind,
      params = params, position = { line = row - 1, character = col },
    }
    symbols[#symbols + 1] = symbol
    definitions[name] = definitions[name] or symbol
    definitions[base] = definitions[base] or symbol
    identifiers[base] = identifiers[base] or symbol
    if params then
      for _, param in ipairs(params) do
        local id = param:match('([%a_][%w_]*)')
        if id then identifiers[id] = identifiers[id] or { name = id, base = id, kind = 6 } end
      end
    end
  end

  for row, line in ipairs(doc_lines) do
    local name, tail = line:match('^%s*local%s+function%s+([%a_][%w_]*)%s*%((.*)$')
    if not name then name, tail = line:match('^%s*function%s+([%a_][%w_%.:]*)%s*%((.*)$') end
    if not name then name, tail = line:match('^%s*local%s+([%a_][%w_]*)%s*=%s*function%s*%((.*)$') end
    if not name then name, tail = line:match('^%s*([%a_][%w_%.:]*)%s*=%s*function%s*%((.*)$') end
    if name then
      add(name, row, name:find(':', 1, true) and 6 or 12, declaration_params(doc_lines, row, tail))
    else
      local locals = line:match('^%s*local%s+([^=]+)')
      if locals and not locals:match('^function%s') then
        for local_name in locals:gmatch('[%a_][%w_]*') do add(local_name, row, 13) end
      end
    end
  end
  return definitions, symbols, identifiers
end

local function signature_label(name, params)
  return ('%s(%s)'):format(name, table.concat(params or {}, ', '))
end

local function snippet(label, params)
  local args = {}
  for i, param in ipairs(params) do
    args[i] = ('${%d:%s}'):format(i, param:gsub('%?$', ''))
  end
  return ('%s(%s)$0'):format(label, table.concat(args, ', '))
end

local function completion_items(document, position, snippet_support)
  local line = document.lines[(position.line or 0) + 1] or ''
  local before = line:sub(1, (position.character or 0) + 1)
  local owner = before:match('([%a_][%w_%.]*)%.[%w_]*$')
  local source = MEMBER_COMPLETIONS[owner] or COMPLETIONS

  local prefix = before:match('([%a_][%w_]*)$') or ''
  local items, seen = {}, {}
  local function add(label, spec)
    local signatures = spec.overloads or (spec.params and { spec.params })
    if not signatures then
      items[#items + 1] = {
        label = label, detail = spec.detail, documentation = spec.detail,
        kind = spec.kind or 3, insertText = label,
      }
      return
    end
    for i, params in ipairs(signatures) do
      local item = {
        label = signature_label(label, params),
        filterText = label,
        detail = spec.detail,
        documentation = spec.detail,
        kind = spec.kind or 3,
        insertText = label,
        sortText = ('%s:%02d'):format(label, i),
      }
      if snippet_support then
        item.insertText = snippet(label, params)
        item.insertTextFormat = 2
      end
      items[#items + 1] = item
    end
  end
  for label, spec in pairs(source) do
    if label:sub(1, #prefix) == prefix then
      add(label, spec)
      seen[label] = true
    end
  end
  for label, symbol in pairs(document.identifiers) do
    if not seen[label] and label:sub(1, #prefix) == prefix then
      add(label, { detail = 'Local Lua symbol', params = symbol.params, kind = symbol.kind or 6 })
    end
  end
  table.sort(items, function(a, b) return a.label < b.label end)
  return { isIncomplete = false, items = items }
end

local function symbol_range(position, name)
  return {
    start = position,
    ['end'] = { line = position.line, character = position.character + #name },
  }
end

local function diagnostic(text)
  local chunk, err = load(text, 'lsp.lua', 't', {})
  if chunk then return {} end
  local row, message = tostring(err):match(':(%d+):%s*(.*)$')
  row = math.max(0, (tonumber(row) or 1) - 1)
  return {{
    range = { start = { line = row, character = 0 }, ['end'] = { line = row, character = 1000 } },
    severity = 1,
    source = 'lua_ls',
    message = message or tostring(err),
  }}
end

local function completion_spec(document, name)
  local symbol = document.definitions[name]
  if symbol then return { detail = 'Local Lua symbol', params = symbol.params }, symbol.name end
  local owner, member = name:match('^(.*)%.([%a_][%w_]*)$')
  local source = owner and MEMBER_COMPLETIONS[owner]
  return COMPLETIONS[name] or (source and source[member])
    or VIM_COMPLETIONS[name] or API_COMPLETIONS[name] or TABLE_COMPLETIONS[name], name
end

local function call_at(document, position)
  local before = {}
  for row = 1, (position.line or 0) do before[#before + 1] = document.lines[row] or '' end
  before[#before + 1] = (document.lines[(position.line or 0) + 1] or ''):sub(1, position.character or 0)
  local text = table.concat(before, '\n')
  local depth, commas = 0, 0
  for i = #text, 1, -1 do
    local char = text:sub(i, i)
    if char == ')' then
      depth = depth + 1
    elseif char == '(' then
      if depth == 0 then
        local name = text:sub(1, i - 1):match('([%a_][%w_%.:]*)%s*$')
        if name then return name, commas end
      else
        depth = depth - 1
      end
    elseif char == ',' and depth == 0 then
      commas = commas + 1
    end
  end
end

local function parse_document(text)
  text = tostring(text or '')
  local doc_lines = lines(text)
  local defs, symbols, identifiers = analyze(doc_lines)
  return {
    lines = doc_lines,
    definitions = defs,
    symbols = symbols,
    identifiers = identifiers,
    diagnostics = diagnostic(text),
  }
end

local EMPTY_DOCUMENT = parse_document('')

function M.rpc(dispatchers)
  local documents, closing, next_id, snippet_support = {}, false, 0, false

  local function publish(uri)
    local document = documents[uri]
    if document then
      dispatchers.notification(methods.textDocument_publishDiagnostics, {
        uri = uri,
        diagnostics = document.diagnostics,
      })
    end
  end

  local rpc = {}
  function rpc.request(method, params, callback, on_reply)
    if closing then return false end
    next_id = next_id + 1
    local id, result = next_id
    if method == 'initialize' then
      local completion = params.capabilities and params.capabilities.textDocument
        and params.capabilities.textDocument.completion
      snippet_support = completion and completion.completionItem
        and completion.completionItem.snippetSupport == true
      result = {
        capabilities = {
          positionEncoding = 'utf-8',
          textDocumentSync = 1,
          completionProvider = { triggerCharacters = { '.', ':' } },
          definitionProvider = true,
          hoverProvider = true,
          documentSymbolProvider = true,
          signatureHelpProvider = { triggerCharacters = { '(', ',' } },
        },
        serverInfo = { name = 'Lua Language Server', version = '1' },
      }
    elseif method == methods.shutdown then
      result = vim.NIL
    else
      local uri = params.textDocument and params.textDocument.uri
      local document = documents[uri] or EMPTY_DOCUMENT
      if method == methods.textDocument_completion then
        result = completion_items(document, params.position or {}, snippet_support)
      elseif method == methods.textDocument_definition then
        local pos = params.position or {}
        local name = word_at(document.lines[(pos.line or 0) + 1] or '', pos.character or 0)
        local found = document.definitions[name]
        result = found and { uri = uri, range = symbol_range(found.position, found.name) } or vim.NIL
      elseif method == methods.textDocument_hover then
        local pos = params.position or {}
        local line = document.lines[(pos.line or 0) + 1] or ''
        local name = word_at(line, pos.character or 0)
        local owner = line:sub(1, (pos.character or 0) + 1):match('([%a_][%w_%.]*)%.[%w_]*$')
        if owner then name = owner .. '.' .. name end
        local spec, display = completion_spec(document, name)
        local label = spec and spec.params and signature_label(display, spec.params) or display
        result = spec and { contents = { kind = 'markdown', value = ('`%s`\n\n%s'):format(label, spec.detail) } }
          or vim.NIL
      elseif method == methods.textDocument_signatureHelp then
        local name, active = call_at(document, params.position or {})
        local spec, display
        if name then spec, display = completion_spec(document, name) end
        if not spec and name then spec, display = completion_spec(document, name:match('([%a_][%w_]*)$') or name) end
        if spec and (spec.params or spec.overloads) then
          local signatures = {}
          for _, signature in ipairs(spec.overloads or { spec.params }) do
            local parameters = {}
            for _, param in ipairs(signature) do parameters[#parameters + 1] = { label = param } end
            signatures[#signatures + 1] = {
              label = signature_label(display, signature),
              parameters = parameters,
            }
          end
          result = {
            signatures = signatures,
            activeSignature = 0,
            activeParameter = math.min(active or 0, math.max(0, #signatures[1].parameters - 1)),
          }
        else
          result = vim.NIL
        end
      elseif method == methods.textDocument_documentSymbol then
        result = {}
        for _, symbol in ipairs(document.symbols) do
          local position, name = symbol.position, symbol.name
          result[#result + 1] = {
            name = name, kind = symbol.kind,
            detail = symbol.params and signature_label(name, symbol.params) or nil,
            range = symbol_range(position, name),
            selectionRange = symbol_range(position, name),
          }
        end
        table.sort(result, function(a, b)
          return a.range.start.line < b.range.start.line
            or (a.range.start.line == b.range.start.line and a.name < b.name)
        end)
      end
    end
    callback(nil, result)
    if on_reply then on_reply(id) end
    return true, id
  end

  function rpc.notify(method, params)
    if closing then return false end
    if method == methods.textDocument_didOpen then
      documents[params.textDocument.uri] = parse_document(params.textDocument.text)
      publish(params.textDocument.uri)
    elseif method == methods.textDocument_didChange then
      local change = params.contentChanges and params.contentChanges[#params.contentChanges]
      if change then documents[params.textDocument.uri] = parse_document(change.text) end
      publish(params.textDocument.uri)
    elseif method == methods.textDocument_didClose then
      documents[params.textDocument.uri] = nil
    elseif method == 'exit' then
      closing = true
      dispatchers.on_exit(0, 0)
    end
    return true
  end

  function rpc.is_closing() return closing end
  function rpc.terminate()
    if not closing then
      closing = true
      dispatchers.on_exit(0, 15)
    end
  end
  return rpc
end

function M.start(opts)
  opts = opts or {}
  return vim.lsp.start({
    name = opts.name or 'lua_ls',
    cmd = M.rpc,
    root_dir = opts.root_dir,
    capabilities = opts.capabilities,
    on_attach = opts.on_attach,
    settings = opts.settings,
  }, { bufnr = opts.bufnr or 0, reuse_client = opts.reuse_client })
end

return M
