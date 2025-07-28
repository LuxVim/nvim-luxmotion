local config = require("luxmotion.config")
local state = require("luxmotion.core.state")
local math_utils = require("luxmotion.utils.math")
local animation_utils = require("luxmotion.utils.animation")
local window_utils = require("luxmotion.utils.window")
local buffer_utils = require("luxmotion.utils.buffer")
local scroll_movement = require("luxmotion.scroll.movement")

local M = {}

function M.animate_scroll(start_line, end_line, start_col, end_col, callback)
  local scroll_config = config.get_scroll()
  
  if not scroll_config.enabled then
    vim.cmd('normal! ' .. vim.fn.line('.') .. 'G')
    window_utils.set_cursor_position(end_line, end_col)
    if callback then callback() end
    return
  end
  
  if state.is_scroll_animating() then
    state.stop_scroll_animation()
  end

  if start_line == end_line then
    window_utils.set_cursor_position(end_line, end_col)
    if callback then callback() end
    return
  end

  state.set_scroll_animating(true)
  local start_time = animation_utils.get_current_time()
  
  local duration = scroll_config.duration * 0.6
  local duration_ns = animation_utils.duration_to_nanoseconds(duration)
  local easing_fn = math_utils.get_easing_function(scroll_config.easing)

  local start_topline = window_utils.get_topline()
  local buf_line_count = buffer_utils.get_line_count()
  local end_topline = scroll_movement.calculate_viewport_target(end_line, start_topline)

  local update_fn = function(eased_progress, raw_progress)
    local current_line = animation_utils.interpolate_values(start_line, end_line, eased_progress)
    local current_col = animation_utils.interpolate_values(start_col, end_col, eased_progress)
    local current_topline = animation_utils.interpolate_values(start_topline, end_topline, eased_progress)
    
    local win_height = window_utils.get_height()
    current_topline = math.max(1, math.min(current_topline, buf_line_count - win_height + 1))
    
    window_utils.set_cursor_position(current_line, current_col)
    
    local actual_topline = window_utils.get_topline()
    if math.abs(current_topline - actual_topline) > 0 then
      window_utils.restore_view(current_topline, current_line, current_col)
    end
  end
  
  local complete_fn = function()
    state.set_scroll_animating(false)
    window_utils.restore_view(end_topline, end_line, end_col)
    if callback then callback() end
  end
  
  local animation_loop = animation_utils.create_loop(
    start_time, 
    duration_ns, 
    easing_fn, 
    update_fn, 
    complete_fn
  )
  
  animation_loop()
end

return M