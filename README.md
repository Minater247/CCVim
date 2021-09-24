# CCVim
Yet another Vim clone for ComputerCraft, which I'm trying to make work as well as possible.

You can use [TAB] to exit editing mode.

Features:
- Insert mode
- Append mode
- Opening/Saving files
- Scrolling (both directions)
- Appending files
- Copy / Cut / Paste
- Jumping to lines
- fF/tT jumping, with repeat/repeat reverse (```;```/```,```)
- Tabs (opening multiple files uses tabs)
- Basic syntax highlighting
- Line numbers
- Jumping to matching bracket (currently works with ```{}```,```[]```, and ```()```.
- Commands that require pressing control (type ```:ctrl``` to activate the emulated control key, or ```:ctrl X``` to emulate [control + key X].)


What's currently being worked on:
- The few remaining commands in [this list of VIM commands](https://vim.rtorr.com)
- File browser


What doesn't work:
- CraftOS Mobile
- Setting filetype when inside the file with :set (currently figuring out why)

Fun fact - this README was written in the program!

# Installation
Run ```pastebin run eX0BrfjA``` on your computer.

Or, for manual installation copy ```vim``` and the ```libs``` folder with its contents to the ```/vim/``` folder of your computer.
