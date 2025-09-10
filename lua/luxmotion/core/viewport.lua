-- Consolidated viewport management module
-- Combines functionality from utils/window.lua and utils/buffer.lua
local M = {}

-- Cached viewport information to reduce API calls
local viewport_cache = {
  height = nil,
  width = nil,
  topline = nil,
  buf_line_count = nil,
  last_update = 0,
  cache_duration = 50000000, -- 50ms in nanoseconds
}

local function update_cache_if_needed()
  local current_time = vim.loop.hrtime()
  if current_time - viewport_cache.last_update > viewport_cache.cache_duration then
    viewport_cache.height = vim.api.nvim_win_get_height(0)
    viewport_cache.width = vim.api.nvim_win_get_width(0)
    viewport_cache.topline = vim.fn.line('w0')
    viewport_cache.buf_line_count = vim.api.nvim_buf_line_count(0)
    viewport_cache.last_update = current_time
  end
end

-- Window-related functions
function M.get_window_info()
  update_cache_if_needed()
  return {
    height = viewport_cache.height,
    width = viewport_cache.width,
    topline = viewport_cache.topline,
  }
end

function M.get_height()
  update_cache_if_needed()
  return viewport_cache.height
end

function M.get_width()
  update_cache_if_needed()
  return viewport_cache.width
end

function M.get_topline()
  update_cache_if_needed()
  return viewport_cache.topline
end

function M.get_cursor_position()
  return vim.api.nvim_win_get_cursor(0)
end

function M.set_cursor_position(line, col)
  -- Validate and clamp cursor position to prevent out of bounds errors
  local clamped_line = M.clamp_line(line)
  local clamped_col = M.clamp_column(col, clamped_line)
  vim.api.nvim_win_set_cursor(0, {clamped_line, clamped_col})
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

-- Buffer-related functions
function M.get_buffer_info()
  update_cache_if_needed()
  return {
    line_count = viewport_cache.buf_line_count,
    current_line = vim.api.nvim_get_current_line(),
  }
end

function M.get_line_count()
  update_cache_if_needed()
  return viewport_cache.buf_line_count
end

function M.get_current_line()
  return vim.api.nvim_get_current_line()
end

function M.get_line_length(line_num)
  line_num = line_num or vim.fn.line('.')
  local line = vim.fn.getline(line_num)
  return #line
end

function M.is_valid_line(line_num)
  return line_num >= 1 and line_num <= M.get_line_count()
end

function M.clamp_line(line_num)
  return math.max(1, math.min(line_num, M.get_line_count()))
end

function M.clamp_column(col, line_num)
  line_num = line_num or vim.fn.line('.')
  local line_length = M.get_line_length(line_num)
  return math.max(0, math.min(col, math.max(line_length - 1, 0)))
end

-- Combined viewport calculations
function M.calculate_viewport_target(target_line, current_topline)
  local win_height = M.get_height()
  local buf_line_count = M.get_line_count()
  
  local target_topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(target_topline, buf_line_count - win_height + 1))
end

-- Cache management
function M.invalidate_cache()
  viewport_cache.last_update = 0
end

function M.set_cache_duration(duration_ms)
  viewport_cache.cache_duration = duration_ms * 1000000 -- Convert to nanoseconds
end

return M