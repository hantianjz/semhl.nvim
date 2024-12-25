# semhl.nvim

This is a re-impementation of <a href="https://github.com/jaxbot/semantic-highlight.vim">semantic-highlight.vim</a> in lua targeting neovim, using tree-sitter instead of the hardcoded list.
And most important of all randomly generated colors with much bigger color space, never will symbols collide with the same colors.

Every identifier is a different color, an idea popularized by <a href="https://medium.com/@evnbr/coding-in-color-3a6db2743a1e">Evan Brooks'</a> blog post.

![image](https://github.com/user-attachments/assets/c30a22eb-186a-4805-9589-a2091335d207)


## setup

With Lazy, currently setup function only accept list of file types to enable plugin for.
```
{
  'hantianjz/semhl.nvim',
  opts    = {
    filetypes = { "c", "cpp", "h", "python", "lua", "typescript", "java" },
    max_file_size = 100 * 1024
  }
}
```

# TODO
- Support custom tree-sitter query
- Allow changing highlight priority
- High color generation configurable
- Generate colors based on background colors
- Check for color collision with highlight next that is close in edit distance
