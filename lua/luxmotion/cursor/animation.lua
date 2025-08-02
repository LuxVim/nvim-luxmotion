local config = require("luxmotion.config")
local state = require("luxmotion.core.state")
local animation_core = require("luxmotion.core.animation")
local viewport = require("luxmotion.core.viewport")
local cursor_movement = require("luxmotion.cursor.movement")

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
  local start_time = animation_core.get_current_time()
  
  local duration = cursor_movement.calculate_movement_duration(
    cursor_config.duration, 
    start_line, 
    end_line, 
    start_col, 
    end_col
  )
  
  local duration_ns = animation_core.duration_to_nanoseconds(duration)
  local easing_fn = animation_core.get_easing_function(cursor_config.easing)

  local update_fn = function(eased_progress, raw_progress)
    local current_line = animation_core.interpolate_values(start_line, end_line, eased_progress)
    local current_col = animation_core.interpolate_values(start_col, end_col, eased_progress)
    
    viewport.set_cursor_position(current_line, current_col)
  end
  
  local complete_fn = function()
    state.set_cursor_animating(false)
    viewport.set_cursor_position(end_line, end_col)
  end
  
  local animation_loop = animation_core.create_loop(
    start_time, 
    duration_ns, 
    easing_fn, 
    update_fn, 
    complete_fn
  )
  
  animation_loop()
end

return M