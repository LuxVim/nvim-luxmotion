local config = require("luxmotion.config")
local state = require("luxmotion.core.state")
local animator = require("luxmotion.core.animator")
local math_utils = require("luxmotion.utils.math")

local M = {}

function M.animate_cursor(start_line, end_line, start_col, end_col)
  local cursor_config = config.get_cursor()
  
  if not cursor_config.enabled then
    return
  end
  
  if state.is_cursor_animating() then
    return
  end

  if start_line == end_line and start_col == end_col then
    return
  end

  state.set_cursor_animating(true)
  local start_time = vim.loop.hrtime()
  
  local line_distance = math.abs(end_line - start_line)
  local col_distance = math.abs(end_col - start_col)
  
  local duration = cursor_config.duration
  
  -- For single line or single column movements, use much shorter duration
  if line_distance <= 1 and col_distance <= 1 then
    duration = math.floor(duration * 0.2) -- 50ms for single movements
  elseif line_distance <= 3 or col_distance <= 3 then
    duration = math.floor(duration * 0.4) -- 100ms for short movements
  elseif start_line == end_line and start_col ~= end_col then
    duration = math.floor(duration * 0.6) -- Horizontal movements still faster
  end
  
  local duration_ns = duration * 1000000
  local easing_fn = math_utils.get_easing_function(cursor_config.easing)

  local update_fn = function(eased_progress, raw_progress)
    local current_line = math.floor(math_utils.lerp(start_line, end_line, eased_progress) + 0.5)
    local current_col = math.floor(math_utils.lerp(start_col, end_col, eased_progress) + 0.5)
    
    vim.api.nvim_win_set_cursor(0, {current_line, current_col})
  end
  
  local complete_fn = function()
    state.set_cursor_animating(false)
    vim.api.nvim_win_set_cursor(0, {end_line, end_col})
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