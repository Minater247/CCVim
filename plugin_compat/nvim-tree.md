# Nvim-Tree

**Somewhat Functional**. You will need to edit one file, `lua/nvim-tree/keymap.lua`, to remove the two lines containing `<2-LeftMouse>` and `<2-RightMouse>` as mouse support is not currently implemented.

There are still some bugs - notably, pressing `q` somehow circumvents the normal error path for unknown commands and crashes the editor. There are also some instances where opening an NvimTree window while another is open causes windows to disappear. Certainly ***use this plugin at your own risk***.

You will need to disable devicons, and set up characters to use instead of the UTF-8 icons. A sane default setup is included below, but as long as these options are present you are able to change the strings to whatever you like.

```lua
require("nvim-tree").setup({
    git = {
        enable = false,
    },
    renderer = {
        icons = {
            web_devicons = {
                file = {
                    enable = false,
                },
            },
            glyphs = {
                default = "",
                symlink = "@",
                bookmark = "*",
                modified = "+",
                hidden = ".",
                folder = {
                    arrow_closed = ">",
                    arrow_open = "v",
                    default = "",
                    open = "",
                    empty = "",
                    empty_open = "",
                },
                git = {
                    unstaged = "!",
                    staged = "S",
                    unmerged = "M",
                    renamed = "R",
                    untracked = "?",
                    deleted = "x",
                    ignored = "i",
                },
            }
        },
    },
})
```