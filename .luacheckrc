std = "lua51"
self = false

exclude_files = {
    ".luarocks/**",
    "runtime/**",
    "log/**"
}

globals = {
    "_",
    "__ccvim_input_state",
    "_ENV",
    "_log_caller",
    "Tabpage",
    "LOG_DEBUG",
    "LOG_ERROR",
    "LOG_INTERNAL",
    "arg",
    "apply_terminal_resize",
    "bit",
    "bit32",
    "buffers",
    "ccvim_path",
    "ccvimversion_str",
    "colors",
    "copcall",
    "coxpcall",
    "curtp",
    "curwin",
    "done",
    "enterWindow",
    "fs",
    "global_marks",
    "has_mode",
    "http",
    "jit",
    "keys",
    "lazyredraw_block",
    "lazyredraw_force",
    "loadstring",
    "loadModule",
    "mock",
    "need_redraw",
    "no_cache",
    "options",
    "registers",
    "remaining",
    "screen",
    "setMode",
    "shell",
    "startuptime",
    "tabpages",
    "term",
    "textutils",
    "tty",
    "utf8",
    "vim",
    "vimversion_maj",
    "vimversion_min",
    "vimversion_pat",
    "vimmode",
    "vimversion_str",
    "what_redraw",
    "window",
    "windows",
    "writestartup",
    math = {
        fields = {
            "clamp",
            "type",
        },
    },
    os = {
        fields = {
            "cancelTimer",
            "epoch",
            "pullEvent",
            "startTimer",
        },
    },
}

read_globals = {
    table = {
        fields = {
            "move",
            "pack",
            "unpack",
        },
    },
}

ignore = {
    -- "211", -- unused variable
    -- "212", -- unused argument
    -- "213", -- unused loop variable
    -- "214", -- used variable with unused hint
    -- "231", -- variable is never accessed
    -- "241", -- variable is mutated but never accessed
    -- "311", -- value assigned to variable is overwritten before use
    -- "411", -- redefining local variable
    -- "421", -- shadowing definition of variable
    -- "431", -- shadowing upvalue
    -- "432", -- shadowing upvalue argument
    -- "512", -- empty branch / unreachable-like control-flow warnings
    -- "542", -- empty if branch
    "611", -- line contains only whitespace
    -- "612", -- trailing whitespace
    -- "614", -- trailing semicolon
    -- "631", -- line too long
}
