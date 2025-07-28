local config = require("luxmotion.config")
local state = require("luxmotion.core.state")
local animator = require("luxmotion.core.animator")
local math_utils = require("luxmotion.utils.math")

local M = {}

function M.animate_scroll(start_line, end_line, start_col, end_col, callback)
  local scroll_config = config.get_scroll()
  
  if not scroll_config.enabled then
    vim.cmd('normal! ' .. vim.fn.line('.') .. 'G')
    vim.api.nvim_win_set_cursor(0, {end_line, end_col})
    if callback then callback() end
    return
  end
  
  if state.is_scroll_animating() then
    state.stop_scroll_animation()
  end

  if start_line == end_line then
    vim.api.nvim_win_set_cursor(0, {end_line, end_col})
    if callback then callback() end
    return
  end

  state.set_scroll_animating(true)
  local start_time = vim.loop.hrtime()
  
  local duration = scroll_config.duration * 0.6
  local duration_ns = duration * 1000000
  local easing_fn = math_utils.get_easing_function(scroll_config.easing)

  local start_topline = vim.fn.line('w0')
  local win_height = vim.api.nvim_win_get_height(0)
  local buf_line_count = vim.api.nvim_buf_line_count(0)
  local scrolloff = vim.o.scrolloff

  local end_topline = end_line - math.floor(win_height / 2)
  end_topline = math.max(1, math.min(end_topline, buf_line_count - win_height + 1))

  local update_fn = function(eased_progress, raw_progress)
    local current_line = math.floor(math_utils.lerp(start_line, end_line, eased_progress) + 0.5)
    local current_col = math.floor(math_utils.lerp(start_col, end_col, eased_progress) + 0.5)
    
    local current_topline = math.floor(math_utils.lerp(start_topline, end_topline, eased_progress) + 0.5)
    current_topline = math.max(1, math.min(current_topline, buf_line_count - win_height + 1))
    
    vim.api.nvim_win_set_cursor(0, {current_line, current_col})
    
    local actual_topline = vim.fn.line('w0')
    if math.abs(current_topline - actual_topline) > 0 then
      vim.fn.winrestview({topline = current_topline, lnum = current_line, col = current_col, leftcol = 0})
    end
  end
  
  local complete_fn = function()
    state.set_scroll_animating(false)
    vim.fn.winrestview({topline = end_topline, lnum = end_line, col = end_col, leftcol = 0})
    if callback then callback() end
  end
  
  local animation_loop = animator.create_animation_loop(
    start_time, 
    duration_ns, 
    easing_fn, 
    update_fn, 
    complete_fn
  )
  
  animation_loop()
end

return M