local Options = {}

local Error = loadModule("lib.error")
local ExMsg = loadModule("lib.excmd.exmsg")
local AutoCmd = loadModule("lib.autocmd")
local Syntax = loadModule("lib.syntax")
local Fn = loadModule("lib.luaapi.fn")
local VimExpr = loadModule("lib.excmd.vimxpr")
local ScriptSource = loadModule("lib.scriptsource")
local Runtime = loadModule("lib.excmd.runtime")

-- TODO: winhl is currently unhandled anywhere

--- Option definitions: {loc, default, type}
--- loc: "ltw"=local to window, "ltb"=local to buffer, "ltt"=local to tabpage,
---      "got"=global or local to tabpage, "gow"=global or local to window,
---      "gob"=global or local to buffer, "ggg"=global
local opt_defs = {
    autoindent    = {"ltb", true,    "boolean"},
    autoread      = {"gob", true,    "boolean"},
    autowrite     = {"ggg", false,   "boolean"},
    autowriteall  = {"ggg", false,   "boolean"},
    background    = {"ggg", "dark",  "string"},
    backspace     = {"ggg", "indent,eol,start", "string"},
    bomb          = {"ltb", false,   "boolean"},
    breakat       = {"ggg", " \t!@*-+;:,./?", "string"},
    bufhidden     = {"ltb", "",      "string"},
    buflisted     = {"ltb", true,    "boolean"},
    buftype       = {"ltb", "",      "string"},
    cedit         = {"ggg", "<C-F>", "string"},
    cindent       = {"ltb", false,   "boolean"},
    cinoptions    = {"ltb", "",      "string"},
    cmdheight     = {"got", 1,       "number"},
    colorcolumn   = {"ltw", "",      "string"},
    columns       = {"ggg", 80,      "number"},
    comments      = {"ltb", "s1:/*,mb:*,ex:*/,://,b:#,:%,:XCOMM,n:>,fb:-", "string"},
    commentstring = {"ltb", "",      "string"},
    completeopt   = {"gob", "menu,popup", "string"},
    completefunc  = {"ltb", "",      "stringfunc"},
    concealcursor = {"ltw", "",      "string"},
    conceallevel  = {"ltw", 0,       "number"},
    copyindent    = {"ltb", false,   "boolean"},
    cpoptions     = {"ggg", "aABceFs_", "string"},
    cursorcolumn  = {"ltw", false,   "boolean"},
    cursorline    = {"ltw", false,   "boolean"},
    cursorlineopt = {"ltw", "both",  "string"},
    define        = {"gob", "",      "string"},
    diff          = {"ltw", false,   "boolean"},
    encoding      = {"ggg", "utf-8", "string"},
    equalalways   = {"ggg", true,    "boolean"},
    eventignore   = {"ggg", "",      "string"},
    expandtab     = {"ltb", false,   "boolean"},
    fileencoding  = {"ltb", "",      "string"},
    fileformat    = {"ltb", "unix",  "string"},
    fileformats   = {"ggg", "unix,dos", "string"},
    filetype      = {"ltb", "",      "string"},
    findfunc      = {"gob", "",      "stringfunc"},
    fillchars     = {"gow", "",      "string"},
    foldcolumn    = {"ltw", "0",     "string"},
    foldenable    = {"ltw", true,    "boolean"},
    foldexpr      = {"ltw", "0",     "string"},
    foldmethod    = {"ltw", "manual","string"},
    foldopen      = {"ggg", "block,hor,mark,percent,quickfix,search,tag,undo", "string"},
    formatoptions = {"ltb", "tcqj",  "string"},
    gdefault      = {"ggg", false,   "boolean"},
    guicursor     = {
        "ggg",
        "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,t:block-blinkon500-blinkoff500-TermCursor",
        "string"
    },
    guioptions    = {"ggg", "egmrLT","string"},
    hidden        = {"ggg", true,    "boolean"},
    include       = {"gob", "",      "string"},
    includeexpr   = {"ltb", "",      "string"},
    ignorecase    = {"ggg", false,   "boolean"},
    indentexpr    = {"ltb", "",      "string"},
    indentkeys    = {"ltb", "0{,0},0),0],:,0#,!^F,o,O,e", "string"},
    insertmode    = {"ggg", false,   "boolean"},
    iskeyword     = {"ltb", "@,48-57,_,192-255", "string"},
    keywordprg    = {"gob", ":Man",  "string"},
    lazyredraw    = {"ggg", false,   "boolean"},
    linebreak     = {"ltw", false,   "boolean"},
    listchars     = {"gow", "tab:> ,trail:-,nbsp:+", "string"},
    laststatus    = {"ggg", 2,       "number"},
    lines         = {"ggg", 24,      "number"},
    list          = {"ltw", false,   "boolean"},
    loadplugins   = {"ggg", true,    "boolean"},
    magic         = {"ggg", true,    "boolean"},
    matchpairs    = {"ltb", "(:),{:},[:],<:>", "string"},
    mouse         = {"ggg", "nvi",   "string"},
    mousemodel    = {"ggg", "popup_setpos", "string"},
    mousemoveevent= {"ggg", false,   "boolean"},
    mousescroll   = {"ggg", "ver:3,hor:6", "string"},
    mousetime     = {"ggg", 500,     "number"},
    modified      = {"ltb", false,   "boolean"},
    modifiable    = {"ltb", true,    "boolean"},
    number        = {"ltw", false,   "boolean"},
    numberwidth   = {"ltw", 4,       "number"},
    omnifunc      = {"ltb", "",      "stringfunc"},
    operatorfunc  = {"ggg", "",      "stringfunc"},
    packpath      = {"ggg", ccvim_path .. "/runtime", "string"},
    path          = {"gob", ".,,",   "string"},
    previewwindow = {"ltw", false,   "boolean"},
    pumblend      = {"ggg", 0,       "number"},
    pumheight     = {"ggg", 0,       "number"},
    pumwidth      = {"ggg", 15,      "number"},
    quickfixtextfunc = {"ggg", "",   "stringfunc"},
    readonly      = {"ltb", false,   "boolean"},
    relativenumber= {"ltw", false,   "boolean"},
    report        = {"ggg", 2,       "number"},
    runtimepath   = {"ggg", ccvim_path .. "/runtime," .. ccvim_path .. "/runtime/after", "string"},
    shell         = {"ggg", "sh",    "string"},
    shiftwidth    = {"ltb", 8,       "number"},
    shortmess     = {"ggg", "ltToOCF", "string"},
    selectmode    = {"ggg", "",      "string"},
    selection     = {"ggg", "inclusive", "string"},
    showcmd       = {"ggg", true,    "boolean"},
    showcmdloc    = {"ggg", "last",  "string"},
    showmode      = {"ggg", true,    "boolean"},
    showtabline   = {"ggg", 1,       "number"},
    signcolumn    = {"ltw", "auto",  "string"},
    smartcase     = {"ggg", false,   "boolean"},
    smarttab      = {"ggg", true,    "boolean"},
    softtabstop   = {"ltb", 0,       "number"},
    spell         = {"ltw", false,   "boolean"},
    splitbelow    = {"ggg", false,   "boolean"},
    splitright    = {"ggg", false,   "boolean"},
    startofline   = {"ggg", true,    "boolean"},
    statusline    = {"gow", "%<%f %h%w%m%r%=%-10.(%l,%c%V%) %P", "string"},
    syntax        = {"ltb", "",      "string"},
    swapfile      = {"ltb", true,    "boolean"},
    suffixesadd   = {"ltb", "",      "string"},
    synmaxcol     = {"ltb", 3000,    "number"},
    tagfunc       = {"ltb", "",      "stringfunc"},
    tabline       = {"ggg", "",      "string"},
    tabstop       = {"ltb", 8,       "number"},
    termguicolors = {"ggg", false,   "boolean"},
    thesaurusfunc = {"gob", "",      "stringfunc"},
    textwidth     = {"ltb", 0,       "number"},
    timeout       = {"ggg", true,    "boolean"},
    timeoutlen    = {"ggg", 1000,    "number"},
    undofile      = {"gob", false,   "boolean"},
    undolevels    = {"gob", 1000,    "number"},
    updatecount   = {"ggg", 200,     "number"},
    varsofttabstop= {"ltb", "",      "string"},
    vartabstop    = {"ltb", "",      "string"},
    verbose       = {"ggg", 0,       "number"},
    virtualedit   = {"gow", "",      "string"},
    wildignore    = {"ggg", "",      "string"},
    winblend      = {"ltw", 0,       "number"},
    winfixheight  = {"ltw", false,   "boolean"},
    winfixwidth   = {"ltw", false,   "boolean"},
    winheight     = {"ggg", 1,       "number"},
    winhighlight  = {"ltw", "",      "string"},
    winminheight  = {"ggg", 1,       "number"},
    winminwidth   = {"ggg", 1,       "number"},
    winwidth      = {"ggg", 20,      "number"},
    wrap          = {"ltw", false,   "boolean"},
    write         = {"ggg", true,    "boolean"},
}

local function option_loc(name)
    return opt_defs[name][1]
end

local function option_default(name)
    return opt_defs[name][2]
end

local function option_type(name)
    return opt_defs[name][3]
end

local opt_defaults_vim = {}
local opt_defaults_vi = {}

local function_option_name_by_ref = setmetatable({}, { __mode = "k" })
local function_option_lambda_counter = 0

local function _expected_option_type(name)
    local typ = option_type(name)
    if typ == "stringfunc" then
        return "string|function"
    end
    return typ
end

local function _is_valid_option_type(name, value)
    local typ = option_type(name)
    if typ == "stringfunc" then
        local tv = type(value)
        return tv == "string" or tv == "function"
    end
    return type(value) == typ
end

local function _name_for_option_function(fn)
    local known = function_option_name_by_ref[fn]
    if known then
        return known
    end

    local name = Fn._funcref_name(fn)

    if type(name) ~= "string" or name == "" then
        function_option_lambda_counter = function_option_lambda_counter + 1
        name = "<lambda>" .. tostring(function_option_lambda_counter)
    end

    function_option_name_by_ref[fn] = name
    Fn._register_funcref(name, fn)
    return name
end

local function _normalize_mouse_flags(value)
    local v = value:gsub("^%s+", ""):gsub("%s+$", "")
    local out = {}
    for i = 1, #v do
        local ch = v:sub(i, i)
        for j = #out, 1, -1 do
            if out[j] == ch then
                table.remove(out, j)
                break
            end
        end
        out[#out + 1] = ch
    end
    return table.concat(out)
end

local function _normalize_option_value(name, value, source_expr)
    if name == "bufhidden" and type(value) == "string" then
        local v = tostring(value):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        local allowed = {
            [""] = true,
            hide = true,
            unload = true,
            delete = true,
            wipe = true,
        }
        if not allowed[v] then
            error(Error(474, "Invalid value for 'bufhidden': " .. tostring(value)))
        end
        return v
    end

    if name == "mouse" and type(value) == "string" then
        local v = _normalize_mouse_flags(value)
        local allowed = {
            n = true,
            v = true,
            i = true,
            c = true,
            h = true,
            a = true,
            r = true,
        }
        for i = 1, #v do
            local ch = v:sub(i, i)
            if not allowed[ch] then
                error(Error(539, ch, source_expr))
            end
        end
        return v
    end

    if name == "mousemodel" and type(value) == "string" then
        local v = tostring(value):gsub("^%s+", ""):gsub("%s+$", ""):lower()
        if v ~= "extend" and v ~= "popup" and v ~= "popup_setpos" then
            error(Error(474, "Invalid value for 'mousemodel': " .. tostring(value)))
        end
        return v
    end

    if name == "mousetime" and type(value) == "number" then
        if value < 0 then
            return 0
        end
        return math.floor(value)
    end

    if option_type(name) == "stringfunc" then
        if value == nil then
            return ""
        end
        if type(value) == "function" then
            return _name_for_option_function(value)
        end
        if type(value) == "string" then
            return value
        end
    end
    return value
end

local expr_option_state_by_window = setmetatable({}, { __mode = "k" })
local expr_option_specs = {
    foldexpr = {
        loc = "ltw",
    },
}

local function _current_script_ctx()
    return ScriptSource.CurrentContext()
end

local function _capture_expr_option_state(name)
    local spec = expr_option_specs[name]
    if not spec then
        return nil
    end
    return Runtime.CaptureDurableScriptState({
        script_ctx = _current_script_ctx(),
    })
end

local function _canonicalize_expr_option_string(name, value)
    local spec = expr_option_specs[name]
    if not spec or type(value) ~= "string" then
        return value
    end

    local lead, fn_name, tail = value:match("^(%s*)(s:[%w_#]+)(%s*%b().*)$")
    if not fn_name then
        lead, fn_name, tail = value:match("^(%s*)(<SID>[%w_#]+)(%s*%b().*)$")
    end
    if not fn_name then
        return value
    end

    local canon = Runtime.CanonicalFunctionName(fn_name, {
        script_ctx = _current_script_ctx(),
    })
    if type(canon) ~= "string" or canon == "" then
        return value
    end
    return lead .. canon .. tail
end

local function _set_expr_option_state(name, window, state)
    local spec = expr_option_specs[name]
    if not spec or not window then
        return
    end
    local bucket = expr_option_state_by_window[window]
    if not bucket then
        bucket = {}
        expr_option_state_by_window[window] = bucket
    end
    bucket[name] = state
end

local function _get_expr_option_state(name, window)
    local spec = expr_option_specs[name]
    if not spec or not window then
        return nil
    end
    local bucket = expr_option_state_by_window[window]
    return bucket and bucket[name]
end

local function _apply_expr_option_state(name, loc, window, state)
    local spec = expr_option_specs[name]
    if spec and loc == spec.loc then
        _set_expr_option_state(name, window, state)
    end
end

function Options.GetExprOptionScriptState(name, window, _buffer)
    local canon = Options.resolve_abbrev(name) or name
    return _get_expr_option_state(canon, window)
end

function Options.EvalExprOption(name, expr, window, buffer, vscope)
    local canon = Options.resolve_abbrev(name) or name
    expr = tostring(expr or "")

    local durable = Options.GetExprOptionScriptState(canon, window, buffer)
    local state = Runtime.MakeRuntimeState(durable, vscope)

    local ok, rv = Runtime.EvalExpression(expr, {
        state = state,
    })
    if not ok then
        return rv, false
    end
    return rv, true
end

local opt_aliases = {
    ai = "autoindent",
    ar = "autoread",
    aw = "autowrite",
    awa = "autowriteall",
    bg = "background",
    bs = "backspace",
    bh = "bufhidden",
    bl = "buflisted",
    brk = "breakat",
    bt = "buftype",
    ch = "cmdheight",
    cc = "colorcolumn",
    co = "columns",
    ci = "copyindent",
    cin = "cindent",
    cino = "cinoptions",
    cot = "completeopt",
    com = "comments",
    cms = "commentstring",
    cocu = "concealcursor",
    cole = "conceallevel",
    cfu = "completefunc",
    cpo = "cpoptions",
    cuc = "cursorcolumn",
    cul = "cursorline",
    culopt = "cursorlineopt",
    def = "define",
    enc = "encoding",
    ea = "equalalways",
    ei = "eventignore",
    et = "expandtab",
    fenc = "fileencoding",
    ff = "fileformat",
    ffs = "fileformats",
    ffu = "findfunc",
    ft = "filetype",
    fcs = "fillchars",
    fdc = "foldcolumn",
    fen = "foldenable",
    fde = "foldexpr",
    fdm = "foldmethod",
    fdo = "foldopen",
    fo = "formatoptions",
    gcr = "guicursor",
    hid = "hidden",
    inc = "include",
    inex = "includeexpr",
    ic = "ignorecase",
    inde = "indentexpr",
    indk = "indentkeys",
    im = "insertmode",
    isk = "iskeyword",
    kp = "keywordprg",
    lz = "lazyredraw",
    lbr = "linebreak",
    lcs = "listchars",
    ls = "laststatus",
    lpl = "loadplugins",
    gd = "gdefault",
    mps = "matchpairs",
    mousem = "mousemodel",
    mousemev = "mousemoveevent",
    mouset = "mousetime",
    mod = "modified",
    ma = "modifiable",
    nu = "number",
    nuw = "numberwidth",
    ofu = "omnifunc",
    opfunc = "operatorfunc",
    pp = "packpath",
    pa = "path",
    pb = "pumblend",
    ph = "pumheight",
    pw = "pumwidth",
    pvw = "previewwindow",
    qftf = "quickfixtextfunc",
    ro = "readonly",
    rnu = "relativenumber",
    rtp = "runtimepath",
    sh = "shell",
    sw = "shiftwidth",
    shm = "shortmess",
    scl = "signcolumn",
    scs = "smartcase",
    sc = "showcmd",
    sloc = "showcmdloc",
    sel = "selection",
    slm = "selectmode",
    smd = "showmode",
    stal = "showtabline",
    sta = "smarttab",
    sts = "softtabstop",
    spr = "splitright",
    sb = "splitbelow",
    sol = "startofline",
    stl = "statusline",
    syn = "syntax",
    sua = "suffixesadd",
    swf = "swapfile",
    smc = "synmaxcol",
    tfu = "tagfunc",
    tal = "tabline",
    ts = "tabstop",
    tsrfu = "thesaurusfunc",
    tw = "textwidth",
    tgc = "termguicolors",
    to = "timeout",
    tm = "timeoutlen",
    udf = "undofile",
    ul = "undolevels",
    uc = "updatecount",
    ve = "virtualedit",
    vsts = "varsofttabstop",
    vts = "vartabstop",
    winbl = "winblend",
    wfh = "winfixheight",
    wfw = "winfixwidth",
    wh = "winheight",
    winhl = "winhighlight",
    wmh = "winminheight",
    wmw = "winminwidth",
    wiw = "winwidth",
    wig = "wildignore",

    -- legacy
    go = "guioptions",

    -- removed (vim_diff.txt "nvim-removed")
    al = "aleph",
    bdlay = "balloondelay",
    beval = "ballooneval",
    bexpr = "balloonexpr",
    cp = "compatible",
    cm = "cryptmethod",
    ed = "edcompatible",
    gfs = "guifontset",
    hk = "hkmap",
    hkp = "hkmapp",
    imaf = "imactivatefunc",
    imak = "imactivatekey",
    imsf = "imstatusfunc",
    mco = "maxcombine",
    pt = "pastetoggle",
    rs = "restorescreen",
    sn = "shortname",
    sws = "swapsync",
    tenc = "termencoding",
    tb = "toolbar",
    tbis = "toolbariconsize",
    tbi = "ttybuiltin",
    tf = "ttyfast",
    ttym = "ttymouse",
    tsl = "ttyscroll",
    tty = "ttytype",
    vbs = "verbose",
}

local option_set_info = {
    global = {},
    win = {},
    buf = {},
    tab = {},
}

local function record_option_set(name, scope_name, key)
    local scope_tbl = option_set_info[scope_name]
    if not scope_tbl then
        return
    end

    scope_tbl[key] = scope_tbl[key] or {}
    scope_tbl[key][name] = {
        was_set = true,
        last_set_sid = 0,
        last_set_linenr = 0,
        last_set_chan = 0,
    }
end

local function map_loc_to_scope(loc)
    if loc == "ltw" or loc == "gow" then
        return "win"
    end
    if loc == "ltb" or loc == "gob" then
        return "buf"
    end
    return "global"
end

local function option_is_global_local(loc)
    return loc == "gob" or loc == "gow" or loc == "got"
end

local function has_local_value(name, loc, window, buffer)
    if loc == "ltw" or loc == "gow" then
        return window.opts[name] ~= nil
    end
    if loc == "ltb" or loc == "gob" then
        return buffer.opts[name] ~= nil
    end
    if loc == "ltt" or loc == "got" then
        return tabpages[curtp].opts[name] ~= nil
    end
    return false
end

local legacy_options = {}

-- Removed options: return defaults on get, but setting is not supported.
local removed_options = {
    aleph = 0,
    antialias = false,
    balloondelay = 0,
    ballooneval = false,
    balloonexpr = "",
    bioskey = false,
    conskey = false,
    compatible = false,
    cryptmethod = "blowfish2",
    key = "",
    cscopepathcomp = 0,
    cscopeprg = "cscope",
    cscopequickfix = "",
    cscoperelative = false,
    cscopetag = false,
    cscopetagorder = 0,
    cscopeverbose = false,
    edcompatible = false,
    encoding = "utf-8",
    esckeys = true,
    guifontset = "",
    guipty = false,
    highlight = "8:SpecialKey,~:EndOfBuffer,@:NonText,d:Directory,e:ErrorMsg,i:IncSearch,l:Search,y:CurSearch,m:MoreMsg,M:ModeMsg,n:LineNr,a:LineNrAbove,b:LineNrBelow,N:CursorLineNr,G:CursorLineSign,O:CursorLineFold,r:Question,s:StatusLine,S:StatusLineNC,c:VertSplit,t:Title,v:Visual,V:VisualNOS,w:WarningMsg,W:WildMenu,f:Folded,F:FoldColumn,A:DiffAdd,C:DiffChange,D:DiffDelete,T:DiffText,E:DiffTextAdd,>:SignColumn,-:Conceal,B:SpellBad,P:SpellCap,R:SpellRare,L:SpellLocal,+:Pmenu,=:PmenuSel,k:PmenuMatch,<:PmenuMatchSel,[:PmenuKind,]:PmenuKindSel,{:PmenuExtra,}:PmenuExtraSel,x:PmenuSbar,X:PmenuThumb,*:TabLine,#:TabLineSel,_:TabLineFill,!:CursorColumn,.:CursorLine,o:ColorColumn,q:QuickFixLine,z:StatusLineTerm,Z:StatusLineTermNC,g:MsgArea,h:ComplMatchIns,%:TabPanel,^:TabPanelSel,&:TabPanelFill,I:PreInsert", -- luacheck: ignore 631
    hkmap = false,
    hkmapp = false,
    pastetoggle = "",
    imactivatefunc = "",
    imactivatekey = "",
    imstatusfunc = "",
    macatsui = false,
    maxcombine = 6, -- Nvim always displays up to 6 combining characters.
    maxmem = 0, -- Nvim delegates memory management to the OS.
    maxmemtot = 0,
    printdevice = "",
    printencoding = "",
    printexpr = "system('lpr' . (&printdevice == '' ? '' : ' -P' . &printdevice) . ' ' . v:fname_in) . delete(v:fname_in) + v:shell_error", -- luacheck: ignore 631
    printfont = "courier",
    printheader = "%<%f%h%m%=Page %N",
    printmbcharset = "",
    prompt = true,
    remap = true,
    restorescreen = false,
    secure = false,
    shelltype = 0,
    shortname = false,
    swapsync = "fsync",
    termencoding = "",
    terse = false,
    textauto = true,
    textmode = false,
    toolbar = "",
    toolbariconsize = "",
    ttybuiltin = true,
    ttyfast = true,
    ttymouse = "",
    ttyscroll = 999,
    ttytype = "",
    ["t_Co"] = 16,
    weirdinvert = false,
}

--[[
    csl -> if string exists, add a comma. Otherwise, append each item normally.
]]
local append_type_special = {
    cinoptions = "csl",
    comments = "csl",
    indentkeys = "csl",
    eventignore = "csl",
    iskeyword = "csl",
    packpath = "csl",
    path = "csl",
    runtimepath = "csl",
    selectmode = "csl",
    suffixesadd = "csl",
    wildignore = "csl",
    mouse = "flags",
}

function Options._append_type(name)
    local opt_name = Options.resolve_abbrev(name)

    if not opt_name then
        error("UNHANDLED OPTION APPEND: " .. name)
    end

    return append_type_special[opt_name]
end

function Options.resolve_abbrev(name)
    name = tostring(name)
    if opt_defs[name] or legacy_options[name] or removed_options[name] ~= nil then return name end
    if opt_aliases[name] then return opt_aliases[name] end
    return nil
end

function Options.get_info(name)
    local canon = Options.resolve_abbrev(name)
    if not canon or not opt_defs[canon] then
        return nil
    end

    local loc = option_loc(canon)
    local typ = option_type(canon)
    if typ == "stringfunc" then
        typ = "string"
    end

    local append_kind = append_type_special[canon]

    -- Find shortest alias for shortname field
    local shortname = canon
    for alias, target in pairs(opt_aliases) do
        if target == canon and (#alias < #shortname or (#alias == #shortname and alias < shortname)) then
            shortname = alias
        end
    end

    return {
        name = canon,
        shortname = shortname,
        scope = map_loc_to_scope(loc),
        global_local = option_is_global_local(loc),
        commalist = append_kind == "csl",
        flaglist = append_kind == "flags",
        type = typ,
        default = option_default(canon),
        allows_duplicates = append_kind ~= "flags",
        _loc = loc,
    }
end

function Options.list_all_info_names()
    local out = {}
    for name, _ in pairs(opt_defs) do
        out[#out + 1] = name
    end
    table.sort(out)
    return out
end

function Options.has_local_value(name, window, buffer)
    local canon = Options.resolve_abbrev(name)
    if not canon then
        return false
    end
    local loc = opt_defs[canon] and option_loc(canon)
    if not loc then
        return false
    end
    return has_local_value(canon, loc, window, buffer)
end

local default_set_info = {
    was_set = false,
    last_set_sid = 0,
    last_set_linenr = 0,
    last_set_chan = 0,
}

function Options.get_last_set_info(name, scope, window, buffer)
    local canon = Options.resolve_abbrev(name)
    if not canon then
        return default_set_info
    end

    local slot
    if scope == "buf" then
        local key = buffer and buffer.bufnr or 0
        slot = option_set_info.buf[key]
    elseif scope == "win" then
        local key = window and window.winnr or 0
        slot = option_set_info.win[key]
    elseif scope == "tab" then
        slot = option_set_info.tab[curtp]
    else
        slot = option_set_info.global[0]
    end

    local info = slot and slot[canon]
    if not info then
        return default_set_info
    end

    return info
end

local global_opts = {}

function Options.new_object_local_opts(scope)
    local out = {}
    for name, def in pairs(opt_defs) do
        local loc = def[1]
        local value = global_opts[name]
        if value ~= nil then
            if scope == "buf" and loc == "ltb" then
                out[name] = value
            elseif scope == "win" and loc == "ltw" then
                out[name] = value
            elseif scope == "tab" and loc == "ltt" then
                out[name] = value
            end
        end
    end
    return out
end

local function first2(a, b)
    if a ~= nil then return a else return b end
end

local function first3(a, b, c)
    if a ~= nil then
        return a
    elseif b ~= nil then
        return b
    else
        return c
    end
end

local function unset_global_local_value(name)
    local typ = option_type(name)
    if typ == "string" or typ == "stringfunc" then
        return ""
    end
    if typ == "number" then
        return -123456
    end
    return nil
end

local getters = {
    ggg = function(n)
        return first2(global_opts[n], option_default(n))
    end,
    got = function(n)
        return first3(tabpages[curtp].opts[n], global_opts[n], option_default(n))
    end,
    gow = function(n, win)
        return first3(win.opts[n], global_opts[n], option_default(n))
    end,
    gob = function(n, _, buf)
        return first3(buf.opts[n], global_opts[n], option_default(n))
    end,
    ltw = function(n, win)
        return first2(win.opts[n], option_default(n))
    end,
    ltb = function(n, _, buf)
        return first2(buf.opts[n], option_default(n))
    end,
    ltt = function(n)
        return first2(tabpages[curtp].opts[n], option_default(n))
    end,
}

local local_getters = {
    ggg = function(n)
        return first2(global_opts[n], option_default(n))
    end,
    got = function(n)
        return first3(tabpages[curtp].opts[n], global_opts[n], option_default(n))
    end,
    gow = function(n, win)
        return first2(win.opts[n], unset_global_local_value(n))
    end,
    gob = function(n, _, buf)
        return first2(buf.opts[n], unset_global_local_value(n))
    end,
    ltw = function(n, win)
        return first2(win.opts[n], option_default(n))
    end,
    ltb = function(n, _, buf)
        return first2(buf.opts[n], option_default(n))
    end,
    ltt = function(n)
        return first2(tabpages[curtp].opts[n], option_default(n))
    end,
}

local global_getters = {
    ggg = function(n)
        return first2(global_opts[n], option_default(n))
    end,
    got = function(n)
        return first2(global_opts[n], option_default(n))
    end,
    gow = function(n)
        return first2(global_opts[n], option_default(n))
    end,
    gob = function(n)
        return first2(global_opts[n], option_default(n))
    end
}


--- Get the current value of a given option.
function Options.get(opt_name, window, buffer, getlocal, getglobal)
    local name_orig = opt_name

    opt_name = Options.resolve_abbrev(opt_name)

    if not opt_name then
        error("UNKNOWN OR UNHANDLED OPTION: " .. name_orig)
    end

    if removed_options[opt_name] ~= nil then
        return removed_options[opt_name]
    end

    if legacy_options[opt_name] then
        return legacy_options[opt_name]
    end

    local kind = option_loc(opt_name)
    if not kind then
        error("DEBUG: UNHANDLED OPTION " .. opt_name)
        return Error(518, opt_name)
    end
    local f
    if getlocal then
        f = local_getters[kind]
    elseif getglobal then
        f = global_getters[kind]
        if not f and (kind == "ltb" or kind == "ltw" or kind == "ltt") then
            return first2(global_opts[opt_name], option_default(opt_name))
        end
    else
        f = getters[kind]
    end
    if not f then
        error(
            "Unhandled option type: "
            .. tostring(kind)
            .. (getlocal and " local" or "")
            .. (getglobal and " global" or "")
        )
    end
    return f(opt_name, window, buffer)
end

--- Parse a comma-separated list into an array
function Options.ParseCSL(raw)
    local items, buf = {}, {}
    local i, n = 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" and i < n then
            buf[#buf + 1] = raw:sub(i + 1, i + 1)
            i = i + 2
        elseif c == "," then
            items[#items + 1] = table.concat(buf)
            buf = {}
            i = i + 1
        else
            buf[#buf + 1] = c
            i = i + 1
        end
    end
    items[#items + 1] = table.concat(buf)
    return items
end

function Options.ParseCSLRaw(raw)
    local items, buf_raw, buf_val = {}, {}, {}
    local i, n = 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" and i < n then
            buf_raw[#buf_raw + 1] = "\\"
            buf_raw[#buf_raw + 1] = raw:sub(i + 1, i + 1)
            buf_val[#buf_val + 1] = raw:sub(i + 1, i + 1)
            i = i + 2
        elseif c == "," then
            items[#items + 1] = { raw = table.concat(buf_raw), val = table.concat(buf_val) }
            buf_raw, buf_val = {}, {}
            i = i + 1
        else
            buf_raw[#buf_raw + 1] = c
            buf_val[#buf_val + 1] = c
            i = i + 1
        end
    end
    items[#items + 1] = { raw = table.concat(buf_raw), val = table.concat(buf_val) }
    return items
end

local function split_name_value_raw(raw, sep_set)
    sep_set = sep_set or { [":"] = true, ["="] = true }
    local i, n = 1, #raw
    while i <= n do
        local c = raw:sub(i, i)
        if c == "\\" and i < n then
            i = i + 2 -- skip escaped char
        elseif sep_set[c] then
            return raw:sub(1, i - 1), raw:sub(i + 1), c
        else
            i = i + 1
        end
    end
    return raw, nil, nil
end

local function _request_window_redraw(win)
    if win then
        win.need_redraw = true
    else
        what_redraw["windows"] = true
    end
    need_redraw = true
end

local function _request_full_redraw()
    what_redraw["all"] = true
    need_redraw = true
end

local function _is_window_only_option_redraw(loc, setlocal, setglobal)
    if setglobal then
        return false
    end
    if not setlocal then
        return false
    end
    return loc == "gob" or loc == "gow" or loc == "ltb" or loc == "ltw"
end

local function _request_option_redraw(loc, setlocal, setglobal, win)
    if _is_window_only_option_redraw(loc, setlocal, setglobal) then
        _request_window_redraw(win)
    else
        _request_full_redraw()
    end
end

local keyed_csl_cache = {}
--- Parse a keyed CSL into a named array
function Options.ParseKeyedCSL(raw, sep_set)
    if keyed_csl_cache[raw] then return keyed_csl_cache[raw] end

    local out = {}
    local items = Options.ParseCSLRaw(raw) -- { {raw=..., val=...}, ... }
    local idx = 1
    while idx <= #items do
        local it = items[idx]
        local name_raw, val_raw = split_name_value_raw(it.raw, sep_set)

        if val_raw == nil then
            -- Flag item (no sep)
            local name = name_raw:gsub("\\(.)", "%1")
            if name ~= "" then out[name] = true end
            idx = idx + 1
        else
            -- name<sep>[value]
            local name = name_raw:gsub("\\(.)", "%1")
            local val  = val_raw:gsub("\\(.)", "%1") -- unescape

            if val == "" then
                -- Singular-comma: next list element is empty => should be a comma
                local next_is_empty = (idx + 1 <= #items) and (items[idx + 1].val == "")
                if next_is_empty then
                    val = ","
                    idx = idx + 1 -- consume the empty token
                end
            end
            out[name] = val
            idx = idx + 1
        end
    end
    keyed_csl_cache[raw] = out
    return out
end

function Options.FormatCommentString(text, window, buffer)
    local cms = tostring(Options.get("commentstring", window, buffer) or "")
    local body = tostring(text or "")
    if cms == "" then
        return body
    end

    local s, e = cms:find("%s", 1, true)
    if not s then
        return cms .. body
    end
    return cms:sub(1, s - 1) .. body .. cms:sub(e + 1)
end

local function sync_screen_geometry_from_options()
    local width = Options.get("columns")
    local height = Options.get("lines")
    if screen.width == width and screen.height == height then
        return
    end

    screen.width = width
    screen.height = height
    for _, tabp in pairs(tabpages) do
        tabp:updateFrameview()
    end
    what_redraw["all"] = true
    need_redraw = true
end

local option_updatees = {
    columns = function(_value)
        sync_screen_geometry_from_options()
    end,
    lines = function(_value)
        sync_screen_geometry_from_options()
    end,
    statusline = function(_value, win, _buffer, local_, _global)
        if local_ then
            win.need_redraw = true
        else
            what_redraw["windows"] = true
        end
        need_redraw = true
    end,
    wrap = function(value, win)
        if win then
            if value then
                win.scrollx = 0
            else
                if win.scrolly then win.scrolly[2] = 0 end
            end
            win.need_redraw = true
        else
            what_redraw["windows"] = true
        end
        need_redraw = true
    end,
    list = function(_value, win)
        if win then
            win.need_redraw = true
        else
            what_redraw["windows"] = true
        end
        need_redraw = true
    end,
    listchars = function(_value, _win)
        what_redraw["windows"] = true
        need_redraw = true
    end,
    concealcursor = function(_value, win)
        if win then
            win.need_redraw = true
        else
            what_redraw["windows"] = true
        end
        need_redraw = true
    end,
    conceallevel = function(_value, win)
        if win then
            win.need_redraw = true
        else
            what_redraw["windows"] = true
        end
        need_redraw = true
    end,
    filetype = function(value, _win, buffer, _setlocal, _setglobal, oldvalue)
        if not buffer then
            return
        end

        local newft = tostring(value or "")
        local oldft = tostring(oldvalue or "")
        if newft == "" or newft == oldft then
            return
        end

        LOG_DEBUG("option(filetype): old='%s' new='%s' bufnr=%s", oldft, newft, tostring(buffer.bufnr))

        AutoCmd.Run("FileType", {
            bufnr = buffer.bufnr,
            bufname = buffer.name,
            pattern = newft,
            force = true,
        })
    end,
    syntax = function(value, _win, buffer)
        if not buffer then
            return
        end

        LOG_DEBUG("option(syntax): new='%s' bufnr=%s", tostring(value), tostring(buffer.bufnr))

        Syntax.OnSyntaxOptionSet(buffer, value)

        AutoCmd.Run("Syntax", {
            bufnr = buffer.bufnr,
            bufname = buffer.name,
            pattern = value,
            force = true,
        })

        what_redraw["windows"] = true
        need_redraw = true
    end,
    synmaxcol = function(value, _win, buffer)
        Syntax.OnSynmaxcolOptionSet(buffer, value)

        what_redraw["windows"] = true
        need_redraw = true
    end,
}

function Options.set(name, value, setlocal, window, buffer, setglobal)
    local name_orig = name

    name = Options.resolve_abbrev(name)

    if not name then
        error("UNKNOWN OR UNHANDLED OPTION: " .. name_orig)
    end

    if removed_options[name] ~= nil or legacy_options[name] ~= nil then
        error(Error(519, name))
    end

    local loc = option_loc(name)

    if not loc then
        error("UNKNOWN OR UNHANDLED OPTION: " .. name)
    end

    value = _normalize_option_value(name, value, name .. "=" .. tostring(value))
    if not _is_valid_option_type(name, value) then
        error(
            "Invalid set of option " .. name .. ": expected " .. _expected_option_type(name) .. ", got " .. type(value)
        )
    end
    local expr_state = _capture_expr_option_state(name)

    local oldvalue = nil
    if name == "filetype" and buffer then
        oldvalue = buffer.opts.filetype
    end

    if loc == "ggg" then
        global_opts[name] = value
        record_option_set(name, "global", 0)
    elseif loc == "gob" then
        if setlocal then
            buffer.opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            buffer.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
            record_option_set(name, "global", 0)
        end
    elseif loc == "gow" then
        if setlocal then
            window.opts[name] = value
            record_option_set(name, "win", window.winnr)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            window.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "win", window.winnr)
            record_option_set(name, "global", 0)
        end
    elseif loc == "got" then
        if setlocal then
            tabpages[curtp].opts[name] = value
            record_option_set(name, "tab", curtp)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            tabpages[curtp].opts[name] = value
            global_opts[name] = value
            record_option_set(name, "tab", curtp)
            record_option_set(name, "global", 0)
        end
    elseif loc == "ltt" then
        if setlocal then
            tabpages[curtp].opts[name] = value
            record_option_set(name, "tab", curtp)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            tabpages[curtp].opts[name] = value
            global_opts[name] = value
            record_option_set(name, "tab", curtp)
            record_option_set(name, "global", 0)
        end
    elseif loc == "ltw" then
        if setlocal then
            window.opts[name] = value
            record_option_set(name, "win", window.winnr)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            window.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "win", window.winnr)
            record_option_set(name, "global", 0)
        end
    elseif loc == "ltb" then
        if setlocal then
            buffer.opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
        elseif setglobal then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        else
            buffer.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
            record_option_set(name, "global", 0)
        end
    end

    _apply_expr_option_state(name, loc, window, expr_state)

    local updatee = option_updatees[name]
    if updatee then updatee(value, window, buffer, setlocal, setglobal, oldvalue) end
    _request_option_redraw(loc, setlocal, setglobal, window)
end

local function _unescape(s) return (tostring(s or ""):gsub("\\(.)", "%1")) end
local function _escape_lua_pat(s) return (tostring(s or ""):gsub("(%W)", "%%%1")) end

local function parse_number(s)
    s = tostring(s or "")
    local sign = 1
    if s:sub(1, 1) == "-" then
        sign = -1; s = s:sub(2)
    elseif s:sub(1, 1) == "+" then
        s = s:sub(2)
    end
    if s:sub(1, 2):lower() == "0x" then
        local n = tonumber(s:sub(3), 16); if n then return sign * n end; return nil
    end
    if s:sub(1, 2):lower() == "0o" then
        local n = tonumber(s:sub(3), 8); if n then return sign * n end; return nil
    end
    if #s > 1 and s:sub(1, 1) == "0" and s:match("^[0-7]+$") then
        local n = tonumber(s, 8); if n then return sign * n end; return nil
    end
    local n = tonumber(s, 10); if n then return sign * n end; return nil
end

local function _apply_value(name, value, mode, window, buffer, source_expr)
    local oldvalue = nil
    if name == "filetype" and buffer then
        oldvalue = buffer.opts.filetype
    end

    -- type-check
    value = _normalize_option_value(name, value, source_expr)
    if not _is_valid_option_type(name, value) then
        error(
            "Invalid set of option " .. name .. ": expected " .. _expected_option_type(name) .. ", got " .. type(value)
        )
    end
    local expr_state = _capture_expr_option_state(name)

    local loc = option_loc(name)
    if loc == "ggg" then
        global_opts[name] = value
        record_option_set(name, "global", 0)
    elseif loc == "gob" or loc == "gow" or loc == "got" then
        if mode == "global" then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        elseif mode == "local" then
            if loc == "gob" then
                buffer.opts[name] = value
                record_option_set(name, "buf", buffer.bufnr)
            elseif loc == "gow" then
                window.opts[name] = value
                record_option_set(name, "win", window.winnr)
            else
                tabpages[curtp].opts[name] = value
                record_option_set(name, "tab", curtp)
            end
        else -- "both": set global and current local
            global_opts[name] = value
            record_option_set(name, "global", 0)
            if loc == "gob" then
                buffer.opts[name] = value
                record_option_set(name, "buf", buffer.bufnr)
            elseif loc == "gow" then
                window.opts[name] = value
                record_option_set(name, "win", window.winnr)
            else
                tabpages[curtp].opts[name] = value
                record_option_set(name, "tab", curtp)
            end
        end
    elseif loc == "ltb" then
        if mode == "global" then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        elseif mode == "both" then
            buffer.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
            record_option_set(name, "global", 0)
        else
            buffer.opts[name] = value
            record_option_set(name, "buf", buffer.bufnr)
        end
    elseif loc == "ltw" then
        if mode == "global" then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        elseif mode == "both" then
            window.opts[name] = value
            global_opts[name] = value
            record_option_set(name, "win", window.winnr)
            record_option_set(name, "global", 0)
        else
            window.opts[name] = value
            record_option_set(name, "win", window.winnr)
        end
    elseif loc == "ltt" then
        if mode == "global" then
            global_opts[name] = value
            record_option_set(name, "global", 0)
        elseif mode == "both" then
            tabpages[curtp].opts[name] = value
            global_opts[name] = value
            record_option_set(name, "tab", curtp)
            record_option_set(name, "global", 0)
        else
            tabpages[curtp].opts[name] = value
            record_option_set(name, "tab", curtp)
        end
    else
        error("Unhandled option location: " .. tostring(loc))
    end

    _apply_expr_option_state(name, loc, window, expr_state)

    local updatee = option_updatees[name]
    if updatee then
        updatee(value, window, buffer, mode == "local", mode == "global", oldvalue)
    end
    _request_option_redraw(loc, mode == "local", mode == "global", window)
end

-- =========================
-- Core: parse and apply one :set token
-- token examples:
--   "number", "nonumber", "invnumber", "number!", "wrap?"
--   "tabstop=4", "ts :4", "shiftwidth+=2"
--   "statusline^=\\ %f", "statusline-=foo", "wrap&", "wrap<"
-- Returns true on success; false on error (so the caller can stop).
-- =========================
function Options.exset_token(token, mode, window, buffer)
    local origtoken = token

    mode  = mode or "both"
    token = tostring(token or "")
    if token == "" then return true end

    local function parse_assignment(tok)
        local name, op, rhs = tok:match("^([%w_]+)(%+=)(.*)$")
        if not name then
            name, op, rhs = tok:match("^([%w_]+)(%-=)(.*)$")
        end
        if not name then
            name, op, rhs = tok:match("^([%w_]+)(%^=)(.*)$")
        end
        if not name then
            name, op, rhs = tok:match("^([%w_]+)([:=])(.*)$")
        end
        return name, op, rhs
    end

    -- Suffixes: ?, &, <, !
    local disp, to_def, to_glob, toggle_tail = false, false, false, false
    local def_kind -- "vim" (default) or "vi"
    local neg_prefix, inv_prefix = false, false
    local name, op, rhs = parse_assignment(token)
    if not name then
        while #token > 0 do
            if token:sub(-4) == "&vim" then
                to_def = true
                def_kind = "vim"
                token = token:sub(1, -5)
            elseif token:sub(-3) == "&vi" then
                to_def = true
                def_kind = "vi"
                token = token:sub(1, -4)
            else
                local last = token:sub(-1)
                if last == "?" then
                    disp = true; token = token:sub(1, -2)
                elseif last == "&" then
                    to_def = true; token = token:sub(1, -2)
                elseif last == "<" then
                    to_glob = true; token = token:sub(1, -2)
                elseif last == "!" then
                    toggle_tail = true; token = token:sub(1, -2)
                else
                    break
                end
            end
        end

        -- Prefixes for booleans: no{opt}, inv{opt}
        if token:sub(1, 2) == "no" then
            neg_prefix = true; token = token:sub(3)
        elseif token:sub(1, 3) == "inv" then
            inv_prefix = true; token = token:sub(4)
        end

        name, op, rhs = parse_assignment(token)
        if not name then
            name = token:match("^([%w_]+)$")
            op, rhs = "", ""
        end
    end

    local canon = Options.resolve_abbrev(name or "")
    if not canon then
        return Error(518, origtoken)
    end
    name = canon

    if removed_options[name] ~= nil or legacy_options[name] ~= nil then
        return Error(519, name)
    end
    local typ = option_type(name)

    local is_bare_nonbool = (not op or op == "") and typ ~= "boolean"
    local has_mutating_suffix = to_def or to_glob or toggle_tail or neg_prefix or inv_prefix

    -- Display: requested via ? or bare non-boolean option (no trailing mutator).
    if disp or (is_bare_nonbool and not has_mutating_suffix) then
        local cur = Options.get(name, window, buffer, (mode == "local"), mode == "global")
        if typ == "boolean" then
            ExMsg.echo((cur and "" or "no") .. name)
        else
            ExMsg.echo(name .. "=" .. tostring(cur))
        end
        if not has_mutating_suffix then
            return true
        end
    end

    -- & default
    if to_def then
        local defval = (def_kind == "vi" and opt_defaults_vi[name]) or opt_defaults_vim[name] or option_default(name)
        _apply_value(name, defval, mode, window, buffer, origtoken)
        return true
    end

    -- < copy global -> local
    if to_glob then
        local gval = Options.get(name, window, buffer, false, true) -- global flavor
        _apply_value(name, gval, "local", window, buffer, origtoken)
        return true
    end

    -- Booleans
    if typ == "boolean" then
        if neg_prefix then
            _apply_value(name, false, mode, window, buffer, origtoken); return true
        end
        if inv_prefix or toggle_tail then
            local cur = Options.get(name, window, buffer, (mode ~= "global"))
            _apply_value(name, not cur, mode, window, buffer, origtoken); return true
        end
        if not op or op == "" then
            _apply_value(name, true, mode, window, buffer, origtoken); return true
        end
        if op == "=" or op == ":" then
            return Error(474, origtoken)
        end
        LOG_DEBUG("Invalid operator for boolean option " .. name .. ": " .. tostring(op))
        return false
    end

    -- No operator for non-boolean: already displayed
    if not op or op == "" then return true end
    if op == ":" then op = "=" end

    -- Numbers
    if typ == "number" then
        local cur = Options.get(name, window, buffer, (mode ~= "global")) or 0
        local num = parse_number(_unescape(rhs or ""))
        if not num then
            LOG_DEBUG("Invalid number for " .. name .. ": " .. tostring(rhs)); return false
        end
        if op == "=" then
            _apply_value(name, num, mode, window, buffer, origtoken)
        elseif op == "+=" then
            _apply_value(name, cur + num, mode, window, buffer, origtoken)
        elseif op == "-=" then
            _apply_value(name, cur - num, mode, window, buffer, origtoken)
        else
            LOG_DEBUG("Invalid operator for number option " .. name .. ": " .. op); return false
        end
        return true
    end

    -- Strings
    local cur = Options.get(name, window, buffer, (mode ~= "global")) or ""
    local s   = _unescape(rhs or "")
    s = _canonicalize_expr_option_string(name, s)
    if typ == "stringfunc" and op == "=" then
        local trimmed = s:gsub("^%s+", ""):gsub("%s+$", "")
        local looks_funcexpr =
            trimmed:match("^function%s*%(") ~= nil
            or trimmed:match("^funcref%s*%(") ~= nil
            or (trimmed:sub(1, 1) == "{" and trimmed:sub(-1) == "}" and trimmed:find("->", 1, true) ~= nil)
        if looks_funcexpr then
            local evaluated = VimExpr.evaluate(trimmed)
            if Error.IsError(evaluated) then
                return evaluated
            end
            s = trimmed
        end
    end
    local append_type = Options._append_type(name)
    if op == "=" then
        _apply_value(name, s, mode, window, buffer, origtoken)
    elseif op == "+=" then
        if append_type == "flags" then
            local merged = tostring(cur)
            for i = 1, #s do
                local ch = s:sub(i, i)
                merged = merged:gsub(_escape_lua_pat(ch), "")
                merged = merged .. ch
            end
            _apply_value(name, merged, mode, window, buffer, origtoken)
        elseif append_type == "csl" and cur ~= "" and s ~= "" then
            _apply_value(name, tostring(cur) .. "," .. s, mode, window, buffer, origtoken)
        else
            _apply_value(name, tostring(cur) .. s, mode, window, buffer, origtoken)
        end
    elseif op == "^=" then
        if append_type == "flags" then
            local merged = tostring(cur)
            for i = #s, 1, -1 do
                local ch = s:sub(i, i)
                if not merged:find(ch, 1, true) then
                    merged = ch .. merged
                end
            end
            _apply_value(name, merged, mode, window, buffer, origtoken)
        elseif append_type == "csl" and cur ~= "" and s ~= "" then
            _apply_value(name, s .. "," .. tostring(cur), mode, window, buffer, origtoken)
        else
            _apply_value(name, s .. tostring(cur), mode, window, buffer, origtoken)
        end
    elseif op == "-=" then
        _apply_value(name, tostring(cur):gsub(_escape_lua_pat(s), ""), mode, window, buffer, origtoken)
    else
        LOG_DEBUG("Invalid operator for string option " .. name .. ": " .. op); return false
    end
    return true
end

return Options
