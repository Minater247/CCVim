# CCVim
A newer Vim clone for ComputerCraft, made since I wanted some of the features the previous one didn't have.

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
- Setting syntax type while in file using :set filetype=[FILETYPE]
- Line numbers
- Jumping to matching bracket (currently works with ```{}```,```[]```, and ```()```.
- Commands that require pressing control (type ```:ctrl``` to activate the emulated control key, or ```:ctrl X``` to emulate [control + key X].)
- File explorer
- Support for tapping/clicking bottom line to exit insert/append modes, for use on mobile
- Autoindent


What's currently being worked on:
- The few remaining commands in [this list of VIM commands](https://vim.rtorr.com)
- Optimizing the way multi-line comments are recalculated

Fun fact - this README was written in the program!

# Installation
Run ```pastebin run eX0BrfjA``` on your computer.

Or, for manual installation copy ```vim.lua```, ```.version``` and the ```libs``` folder with its contents to the ```/vim/``` folder of your computer. For syntax, put each syntax file according to extension (ex. ```XYZ.lua``` -> ```/syntax/lua.lua```, ```XYZ.swf``` -> ```/syntax/swf.lua```) in the ```/vim/syntax/``` folder.
