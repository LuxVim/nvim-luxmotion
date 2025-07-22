local math_utils = require("luxmotion.utils.math")

local M = {}

function M.create_animation_loop(start_time, duration_ns, easing_fn, update_fn, complete_fn)
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

function M.animate_values(start_val, end_val, progress_fn)
  return function(eased_progress, raw_progress)
    local current_val = math.floor(math_utils.lerp(start_val, end_val, eased_progress) + 0.5)
    progress_fn(current_val, raw_progress)
  end
end

return M