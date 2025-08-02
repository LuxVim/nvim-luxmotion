local M = {}

M.config = {
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
  performance = {
    enabled = false,
    disable_syntax_during_scroll = true,
    ignore_events = {'WinScrolled', 'CursorMoved', 'CursorMovedI'},
    reduce_frame_rate = false,
    frame_rate_threshold = 30, -- Switch to reduced frame rate under this FPS
    auto_enable_on_large_files = true,
    large_file_threshold = 5000, -- Lines
  },
}

return M
