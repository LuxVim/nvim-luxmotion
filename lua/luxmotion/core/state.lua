local M = {}

M.cursor_animating = false
M.scroll_animating = false

function M.is_cursor_animating()
  return M.cursor_animating
end

function M.is_scroll_animating()
  return M.scroll_animating
end

function M.set_cursor_animating(state)
  M.cursor_animating = state
end

function M.set_scroll_animating(state)
  M.scroll_animating = state
end

function M.stop_cursor_animation()
  M.cursor_animating = false
end

function M.stop_scroll_animation()
  M.scroll_animating = false
end

return M