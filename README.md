# semhl.nvim

This is a re-impementation of <a href="https://github.com/jaxbot/semantic-highlight.vim">semantic-highlight.vim</a> in lua targeting neovim, with some additional new features.

Where every variable is a different color, an idea popularized by <a href="https://medium.com/@evnbr/coding-in-color-3a6db2743a1e">Evan Brooks'</a> blog post.

<img src="https://raw.githubusercontent.com/jaxbot/semantic-highlight.vim/master/semantic-highlight.png">

## Usage

In a file, run `:SemhlLoad` to convert variables into colors. Run `:SemhlUnload` to revert.

## Customization

TBD

## Language support

This plugin is language agnostic, meaning it will work on any language with words. It depend on treesitter parsing to provide all non key word identifiers to highlight.

Currently enabled for:
- C/Cpp
- Lua
- Python
