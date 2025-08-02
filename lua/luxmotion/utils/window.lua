local M = {}

-- Cached window information to reduce API calls
local window_cache = {
  height = nil,
  width = nil,
  topline = nil,
  buf_line_count = nil,
  last_update = 0,
  cache_duration = 50000000, -- 50ms in nanoseconds
}

local function update_cache_if_needed()
  local current_time = vim.loop.hrtime()
  if current_time - window_cache.last_update > window_cache.cache_duration then
    window_cache.height = vim.api.nvim_win_get_height(0)
    window_cache.width = vim.api.nvim_win_get_width(0)
    window_cache.topline = vim.fn.line('w0')
    window_cache.buf_line_count = vim.api.nvim_buf_line_count(0)
    window_cache.last_update = current_time
  end
end

function M.get_info()
  update_cache_if_needed()
  return {
    height = window_cache.height,
    width = window_cache.width,
    topline = window_cache.topline,
  }
end

function M.get_height()
  update_cache_if_needed()
  return window_cache.height
end

function M.get_width()
  update_cache_if_needed()
  return window_cache.width
end

function M.get_topline()
  update_cache_if_needed()
  return window_cache.topline
end

function M.get_cached_buf_line_count()
  update_cache_if_needed()
  return window_cache.buf_line_count
end

function M.invalidate_cache()
  window_cache.last_update = 0
end

function M.get_cursor_position()
  return vim.api.nvim_win_get_cursor(0)
end

function M.set_cursor_position(line, col)
  vim.api.nvim_win_set_cursor(0, {line, col})
end

function M.get_scrolloff()
  return vim.o.scrolloff
end

function M.restore_view(topline, line, col)
  vim.fn.winrestview({
    topline = topline,
    lnum = line,
    col = col,
    leftcol = 0
  })
end

function M.calculate_topline_for_center(target_line, buf_line_count)
  local win_height = M.get_height()
  local topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(topline, buf_line_count - win_height + 1))
end

return M