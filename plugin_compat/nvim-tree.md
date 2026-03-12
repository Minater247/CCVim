# Nvim-Tree

Fully compatible, with some config.

You will need to disable devicons, and set up characters to use instead of the UTF-8 icons. A sane default setup is included below, but as long as these options are present you are able to change the glyphs to whatever you like.

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
            }
        },
    },
})
```
