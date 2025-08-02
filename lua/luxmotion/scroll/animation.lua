local config = require("luxmotion.config")
local state = require("luxmotion.core.state")
local animation_core = require("luxmotion.core.animation")
local viewport = require("luxmotion.core.viewport")
local scroll_movement = require("luxmotion.scroll.movement")

local M = {}

function M.animate_scroll(start_line, end_line, start_col, end_col, callback)
  local scroll_config = config.get_scroll()
  local performance = require("luxmotion.performance")
  
  -- Auto-toggle performance mode based on conditions
  performance.auto_toggle()
  
  if not scroll_config.enabled then
    vim.cmd('normal! ' .. vim.fn.line('.') .. 'G')
    viewport.set_cursor_position(end_line, end_col)
    if callback then callback() end
    return
  end
  
  if state.is_scroll_animating() then
    state.stop_scroll_animation()
  end

  if start_line == end_line then
    viewport.set_cursor_position(end_line, end_col)
    if callback then callback() end
    return
  end

  state.set_scroll_animating(true)
  local start_time = animation_core.get_current_time()
  
  local duration = scroll_config.duration * 0.6
  local duration_ns = animation_core.duration_to_nanoseconds(duration)
  local easing_fn = animation_core.get_easing_function(scroll_config.easing)

  local start_topline = viewport.get_topline()
  local buf_line_count = viewport.get_line_count()
  local end_topline = viewport.calculate_viewport_target(end_line, start_topline)

  local update_fn = function(eased_progress, raw_progress)
    local current_line = animation_core.interpolate_values(start_line, end_line, eased_progress)
    local current_col = animation_core.interpolate_values(start_col, end_col, eased_progress)
    local current_topline = animation_core.interpolate_values(start_topline, end_topline, eased_progress)
    
    local win_height = viewport.get_height()
    current_topline = math.max(1, math.min(current_topline, buf_line_count - win_height + 1))
    
    viewport.set_cursor_position(current_line, current_col)
    
    local actual_topline = viewport.get_topline()
    if math.abs(current_topline - actual_topline) > 0 then
      viewport.restore_view(current_topline, current_line, current_col)
    end
  end
  
  local complete_fn = function()
    state.set_scroll_animating(false)
    viewport.restore_view(end_topline, end_line, end_col)
    if callback then callback() end
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