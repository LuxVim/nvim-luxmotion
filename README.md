# nvim-luxmotion

A comprehensive Neovim plugin that provides smooth cursor navigation and viewport scrolling, combining the functionality of cursor movement plugins and vim-smoothie-style scrolling in one unified solution.

## Features

### Cursor Movement
- Smooth animated cursor movement for `j`, `k`, `h`, `l` keys
- Additional movements: `0` (beginning of line), `$` (end of line)
- Support for count prefixes (e.g., `5j` moves 5 lines smoothly)
- Visual mode support for all cursor movements

### Viewport Scrolling  
- Smooth scrolling for `<C-d>`, `<C-u>`, `<C-f>`, `<C-b>` commands
- Visual mode support for scroll commands with selection preservation
- Smooth positioning with `zz`, `zt`, `zb` commands
- Optional experimental `gg`, `G` smooth jumping

### General
- Configurable animation duration and easing functions for both cursor and scroll
- Independent enable/disable for cursor movement vs viewport scrolling
- Lightweight and performant with 60fps animations
- Prevention of overlapping animations for optimal performance

## Installation

### Using lazy.nvim
```lua
{
  "LuxVim/nvim-luxmotion",
  config = function()
    require("luxmotion").setup({
      cursor = {
        duration = 250,     -- Cursor animation duration in milliseconds
        easing = "ease-out", -- Cursor easing function
        enabled = true,     -- Enable cursor animations
      },
      scroll = {
        duration = 400,     -- Scroll animation duration in milliseconds
        easing = "ease-out", -- Scroll easing function
        enabled = true,     -- Enable scroll animations
      },
      keymaps = {
        cursor = true,      -- Enable hjkl smooth cursor movement
        scroll = true,      -- Enable smooth scrolling keymaps
        experimental = false, -- Enable gg, G experimental mappings
      },
    })
  end,
}
```

### Using packer.nvim
```lua
use {
  "/nvim-luxmotion",
  config = function()
    require("luxmotion").setup()
  end
}
```

### Using vim-plug
```vim
Plug 'LuxVim/nvim-luxmotion'
```

Then in your `init.lua` or `init.vim`:
```lua
lua << EOF
require("luxmotion").setup({
  cursor = {
    duration = 250,
    easing = "ease-out",
    enabled = true,
  },
  scroll = {
    duration = 400,
    easing = "ease-out",
    enabled = true,
  },
  keymaps = {
    cursor = true,
    scroll = true,
    experimental = false,
  },
})
EOF
```

## Configuration

```lua
require("luxmotion").setup({
  cursor = {
    duration = 250,       -- Animation duration for cursor movement (default: 250)
    easing = "ease-out",  -- Easing function for cursor (default: "ease-out")
    enabled = true,       -- Enable cursor animations (default: true)
  },
  scroll = {
    duration = 400,       -- Animation duration for scrolling (default: 400)
    easing = "ease-out",  -- Easing function for scrolling (default: "ease-out")
    enabled = true,       -- Enable scroll animations (default: true)
  },
  keymaps = {
    cursor = true,        -- Enable hjkl keymaps (default: true)
    scroll = true,        -- Enable scroll keymaps (default: true)
    experimental = false, -- Enable gg, G keymaps (default: false)
  },
})
```

### Supported Commands

**Cursor Movement (when `keymaps.cursor = true`):**
- `h`, `j`, `k`, `l` - Smooth cursor movement
- `0` - Smooth move to beginning of line
- `$` - Smooth move to end of line
- Works with count prefixes: `5j`, `10k`, etc.
- Available in both normal and visual modes

**Viewport Scrolling (when `keymaps.scroll = true`):**
- `<C-d>` - Scroll down half-page
- `<C-u>` - Scroll up half-page  
- `<C-f>` - Scroll down full-page
- `<C-b>` - Scroll up full-page
- `zz` - Center cursor in window
- `zt` - Move cursor to top of window
- `zb` - Move cursor to bottom of window
- Scroll commands work in visual mode with selection preservation

**Experimental (when `keymaps.experimental = true`):**
- `gg` - Smooth jump to beginning of file
- `G` - Smooth jump to end of file (or specific line with count)

### Easing Options
- `"linear"` - Linear interpolation
- `"ease-out"` - Cubic ease-out (default)
- `"ease-out-quad"` - Quadratic ease-out

## Commands

### Global Controls
- `:LuxMotionEnable` - Enable both cursor and scroll animations
- `:LuxMotionDisable` - Disable both cursor and scroll animations  
- `:LuxMotionToggle` - Toggle both cursor and scroll animations

### Individual Controls
- `:LuxMotionEnableCursor` - Enable only cursor movement animations
- `:LuxMotionDisableCursor` - Disable only cursor movement animations
- `:LuxMotionEnableScroll` - Enable only scroll animations
- `:LuxMotionDisableScroll` - Disable only scroll animations

## API

```lua
local luxmotion = require("luxmotion")

-- Global enable/disable
luxmotion.enable()    -- Enable both cursor and scroll
luxmotion.disable()   -- Disable both cursor and scroll
luxmotion.toggle()    -- Toggle both

-- Individual controls
luxmotion.enable_cursor()   -- Enable cursor animations only
luxmotion.disable_cursor()  -- Disable cursor animations only
luxmotion.enable_scroll()   -- Enable scroll animations only
luxmotion.disable_scroll()  -- Disable scroll animations only

-- Manual smooth movement
luxmotion.move_smooth("j", 5)        -- Move cursor down 5 lines smoothly
luxmotion.scroll_smooth("ctrl_d", 2) -- Scroll down 2 half-pages smoothly
```

## Customization

### Disable Default Keymaps
```lua
require("luxmotion").setup({
  keymaps = {
    cursor = false,  -- Disable hjkl smooth movement
    scroll = false,  -- Disable scroll smooth movement
    experimental = false,
  },
})

-- Set custom keymaps
vim.keymap.set("n", "j", function()
  require("luxmotion").move_smooth("j", vim.v.count1)
end)

vim.keymap.set("n", "<C-d>", function()
  require("luxmotion").scroll_smooth("ctrl_d", vim.v.count1)
end)
```

### Different Settings for Cursor vs Scroll
```lua
require("luxmotion").setup({
  cursor = {
    duration = 100,      -- Fast cursor movement
    easing = "linear",   -- Linear cursor movement
  },
  scroll = {
    duration = 500,      -- Slower, more dramatic scrolling
    easing = "ease-out", -- Smooth scroll with ease-out
  },
})
```

## Performance

- Uses Neovim's `vim.defer_fn` for smooth 60fps animations
- Separate animation states prevent overlapping cursor and scroll animations
- Optimized viewport calculations reduce unnecessary screen updates
- Respects Neovim settings like `scrolloff` for consistent behavior

## Comparison with Other Plugins

**vs vim-smoothie:**
- ✅ All vim-smoothie scroll commands (`<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`, `zz`, `zt`, `zb`)
- ✅ Optional `gg`, `G` experimental mappings
- ✅ **Plus** smooth cursor movement (`hjkl`)
- ✅ Modern Lua implementation with better performance
- ✅ Independent control of cursor vs scroll animations

**vs neoscroll.nvim:**
- ✅ Similar scroll functionality
- ✅ **Plus** smooth cursor movement
- ✅ More granular configuration options
- ✅ Simpler, more focused implementation


## Acknowledgments

Inspired by [vim-smoothie](https://github.com/psliwka/vim-smoothie) and [neoscroll.nvim](https://github.com/karb94/neoscroll.nvim).

## License

MIT License - see [LICENSE](LICENSE) for details.
