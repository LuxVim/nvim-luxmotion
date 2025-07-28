local math_utils = require("luxmotion.utils.math")

local M = {}

function M.create_loop(start_time, duration_ns, easing_fn, update_fn, complete_fn)
  local function update()
    local current_time = vim.loop.hrtime()
    local elapsed = current_time - start_time
    local progress = math.min(elapsed / duration_ns, 1.0)
    
    local eased_progress = easing_fn(progress)
    
    update_fn(eased_progress, progress)
    
    if progress < 1.0 then
      vim.defer_fn(update, 16)
    else
      complete_fn()
    end
  end
  
  return update
end

function M.interpolate_values(start_val, end_val, eased_progress)
  return math.floor(math_utils.lerp(start_val, end_val, eased_progress) + 0.5)
end

function M.calculate_duration(base_duration, distance_factor)
  return math.floor(base_duration * distance_factor)
end

function M.get_current_time()
  return vim.loop.hrtime()
end

function M.duration_to_nanoseconds(duration_ms)
  return duration_ms * 1000000
end

return M