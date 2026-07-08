# whisk.nvim

Smooth motion animations for Neovim. Provides 60fps fluid animations for cursor movement, word navigation, text objects, and viewport scrolling — all in one plugin.

---

## Features

**Motion coverage** — animates every standard Vim motion:

| Category | Motions |
|----------|---------|
| Basic | `h`, `j`, `k`, `l`, `0`, `$` |
| Word | `w`, `b`, `e`, `W`, `B`, `E` |
| Find/Till | `f`, `F`, `t`, `T` |
| Text Objects | `{`, `}`, `(`, `)`, `%` |
| Line Jumps | `gg`, `G`, `\|` |
| Search | `n`, `N` |
| Screen Lines | `gj`, `gk` |
| Viewport | `<C-d>`, `<C-u>`, `<C-f>`, `<C-b>`, `zz`, `zt`, `zb` |

- Works in Normal and Visual modes with count prefixes (position motions `zz`/`zt`/`zb` are Normal mode only)
- Separate duration and easing for cursor vs scroll animations
- Performance mode with automatic large file detection
- Object pooling (up to 10 reusable animation objects) to reduce garbage collection pressure
- Extensible — define your own keymaps via the orchestrator API, or register custom motions and traits through the registry

---

## Requirements

- Neovim >= 0.8

---

## Installation

The plugin auto-calls `require("whisk").setup()` on load. To disable this and call setup manually, set `g:whisk_auto_setup = 0` before the plugin loads.

### lazy.nvim

```lua
{
  "josstei/whisk.nvim",
  event = "VeryLazy",
  init = function() vim.g.whisk_auto_setup = 0 end,
  opts = {},
}
```

The `init` hook disables the plugin's built-in auto-setup so that lazy.nvim's `opts` is the single source of `setup()`; without it, whisk is configured twice at startup (once on load, once by lazy), leaking a duplicate performance autocmd.

### vim-plug

```vim
Plug 'josstei/whisk.nvim'
```

```lua
require("whisk").setup()
```

---

## Configuration

All options with their defaults:

```lua
require("whisk").setup({
  cursor = {
    duration = 150,
    easing = "ease-out",
    enabled = true,
  },
  scroll = {
    duration = 200,
    easing = "ease-in-out",
    enabled = true,
  },
  keymaps = {
    cursor = true,
    scroll = true,
  },
  performance = {
    enabled = false,
    disable_syntax_during_scroll = true,
    ignore_events = { "WinScrolled", "CursorMoved", "CursorMovedI" },
    reduce_frame_rate = false,
    frame_rate_threshold = 60,    -- not currently read by any code path
    auto_enable_on_large_files = true,
    large_file_threshold = 5000,
  },
})
```

**Easing options:** `linear`, `ease-in`, `ease-out`, `ease-in-out`

---

## Commands

| Command | Description |
|---------|-------------|
| `:WhiskEnable` | Enable all animations |
| `:WhiskDisable` | Disable all animations |
| `:WhiskToggle` | Toggle all animations |
| `:WhiskEnableCursor` | Enable cursor animations |
| `:WhiskDisableCursor` | Disable cursor animations |
| `:WhiskEnableScroll` | Enable scroll animations |
| `:WhiskDisableScroll` | Disable scroll animations |
| `:WhiskPerformanceEnable` | Enable performance mode |
| `:WhiskPerformanceDisable` | Disable performance mode |
| `:WhiskPerformanceToggle` | Toggle performance mode |

---

## Lua API

```lua
local whisk = require("whisk")

whisk.enable()
whisk.disable()
whisk.toggle()

whisk.enable_cursor()
whisk.disable_cursor()
whisk.enable_scroll()
whisk.disable_scroll()

whisk.toggle_performance()

whisk.reset()              -- tear down keymaps, stop animations, clear registries, remove lifecycle autocmds
```

### Performance module

```lua
local performance = require("whisk.performance")

performance.enable()
performance.disable()
performance.is_active()
performance.get_current_fps()
performance.get_frame_interval()
performance.should_ignore_event(event)
```

### Manual motion execution

For custom keymaps, use the orchestrator directly:

```lua
local orchestrator = require("whisk.engine.orchestrator")

orchestrator.execute("basic_j", { count = 5, direction = "j" })
orchestrator.execute("word_w", { count = 3, direction = "w" })
orchestrator.execute("find_f", { char = "x", count = 1, direction = "f" })
```

### Motion IDs

| Category | IDs |
|----------|-----|
| Basic | `basic_h`, `basic_j`, `basic_k`, `basic_l`, `basic_0`, `basic_$` |
| Word | `word_w`, `word_b`, `word_e`, `word_W`, `word_B`, `word_E` |
| Find | `find_f`, `find_F`, `find_t`, `find_T` |
| Text Object | `text_object_{`, `text_object_}`, `text_object_(`, `text_object_)`, `text_object_%` |
| Line | `line_gg`, `line_G`, `line_\|` |
| Search | `search_n`, `search_N` |
| Screen | `screen_gj`, `screen_gk` |
| Scroll | `scroll_ctrl_d`, `scroll_ctrl_u`, `scroll_ctrl_f`, `scroll_ctrl_b`, `position_zz`, `position_zt`, `position_zb` |

---

## Examples

### Custom keymaps

```lua
require("whisk").setup({
  keymaps = { cursor = false, scroll = false },
})

local orchestrator = require("whisk.engine.orchestrator")
vim.keymap.set("n", "j", function()
  orchestrator.execute("basic_j", { count = vim.v.count1, direction = "j" })
end)
```

### Different speeds for cursor vs scroll

```lua
require("whisk").setup({
  cursor = { duration = 100, easing = "linear" },
  scroll = { duration = 400, easing = "ease-out" },
})
```

### Performance-oriented

```lua
require("whisk").setup({
  cursor = { duration = 100, easing = "linear" },
  scroll = { duration = 150, easing = "linear" },
  performance = { enabled = true },
})
```

---

## Performance mode

When enabled, performance mode:

- Disables syntax highlighting when `disable_syntax_during_scroll` is set (default: on)
- Optionally reduces frame rate from 60fps to 30fps (`reduce_frame_rate = true`)
- Auto-enables on `BufEnter`/`BufWinEnter` for files larger than `large_file_threshold` lines (default: 5000)
- Exposes a configurable `ignore_events` list (default: `WinScrolled`, `CursorMoved`, `CursorMovedI`) for callers to check via `should_ignore_event()`

Toggle at runtime with `:WhiskPerformanceToggle` or `require("whisk").toggle_performance()`.

---

## Behavior notes

- If a motion category is disabled, whisk falls back to native `normal!` motion behavior.
- When a new motion starts while any of its traits are already animating, **all** active animations complete instantly at their final positions before the new animation begins (domination).
- Animations are automatically cancelled when the buffer is deleted (`BufDelete`), the window is closed (`WinClosed`), or the buffer is left (`BufLeave`).
- `gg` with a count (e.g., `5gg`) goes to line N. `|` with a count (e.g., `5|`) goes to column N.

---

## Comparison

| Feature | whisk.nvim | neoscroll.nvim | vim-smoothie |
|---------|------------|----------------|--------------|
| Cursor movement | Yes | No | No |
| Scroll movement | Yes | Yes | Yes |
| Word navigation | Yes | No | No |
| Find/Till | Yes | No | No |
| Text objects | Yes | No | No |
| Search navigation | Yes | No | No |
| Visual mode | Yes | Scroll only | Scroll only |
| Count prefixes | Yes | Scroll only | Scroll only |

---

## Migrating from nvim-luxmotion

whisk.nvim was previously published as nvim-luxmotion. A deprecation shim is included:

- `require("luxmotion")` forwards to `require("whisk")` with a warning.
- All `:LuxMotion*` commands forward to their `:Whisk*` equivalents.
- `g:luxmotion_auto_setup` forwards to `g:whisk_auto_setup`.

Update your config to use `whisk` directly — the shim will be removed in a future release.

---

## Documentation

- [Usage Guide](docs/USAGE.md)
- [Architecture](docs/ARCHITECTURE.md)

---

## License

MIT — see [LICENSE](LICENSE).
