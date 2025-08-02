local config = require("luxmotion.config")
local buffer_utils = require("luxmotion.utils.buffer")

local M = {}

-- Performance mode state
local performance_state = {
  is_active = false,
  original_syntax = nil,
  ignored_events = {},
  event_listeners = {},
}

-- Check if performance mode should be auto-enabled
function M.should_auto_enable()
  local perf_config = config.get_performance()
  if not perf_config.auto_enable_on_large_files then
    return false
  end
  
  local line_count = buffer_utils.get_line_count()
  return line_count > perf_config.large_file_threshold
end

-- Enable performance mode
function M.enable()
  if performance_state.is_active then
    return
  end
  
  local perf_config = config.get_performance()
  
  -- Disable syntax highlighting if configured
  if perf_config.disable_syntax_during_scroll then
    performance_state.original_syntax = vim.bo.syntax
    vim.bo.syntax = "off"
  end
  
  -- Ignore specified events during animations
  for _, event in ipairs(perf_config.ignore_events) do
    performance_state.ignored_events[event] = true
  end
  
  performance_state.is_active = true
end

-- Disable performance mode
function M.disable()
  if not performance_state.is_active then
    return
  end
  
  -- Restore original syntax highlighting
  if performance_state.original_syntax then
    vim.bo.syntax = performance_state.original_syntax
    performance_state.original_syntax = nil
  end
  
  -- Clear ignored events
  performance_state.ignored_events = {}
  
  performance_state.is_active = false
end

-- Check if performance mode is active
function M.is_active()
  return performance_state.is_active
end

-- Get performance-aware frame interval
function M.get_frame_interval()
  local perf_config = config.get_performance()
  
  if performance_state.is_active and perf_config.reduce_frame_rate then
    return 33 -- ~30fps instead of 60fps
  else
    return 16 -- ~60fps
  end
end

-- Check if an event should be ignored
function M.should_ignore_event(event)
  return performance_state.ignored_events[event] or false
end

-- Auto-toggle performance mode based on conditions
function M.auto_toggle()
  local perf_config = config.get_performance()
  
  if perf_config.enabled or M.should_auto_enable() then
    M.enable()
  else
    M.disable()
  end
end

-- Performance monitoring
local perf_stats = {
  frame_times = {},
  current_fps = 60,
  last_frame_time = 0,
}

function M.record_frame_time()
  local current_time = vim.loop.hrtime()
  
  if perf_stats.last_frame_time > 0 then
    local frame_time = (current_time - perf_stats.last_frame_time) / 1000000 -- Convert to ms
    table.insert(perf_stats.frame_times, frame_time)
    
    -- Keep only last 10 frame times
    if #perf_stats.frame_times > 10 then
      table.remove(perf_stats.frame_times, 1)
    end
    
    -- Calculate current FPS
    if #perf_stats.frame_times > 0 then
      local avg_frame_time = 0
      for _, time in ipairs(perf_stats.frame_times) do
        avg_frame_time = avg_frame_time + time
      end
      avg_frame_time = avg_frame_time / #perf_stats.frame_times
      perf_stats.current_fps = 1000 / avg_frame_time
    end
  end
  
  perf_stats.last_frame_time = current_time
end

function M.get_current_fps()
  return perf_stats.current_fps
end

-- Initialize performance monitoring
function M.setup()
  local perf_config = config.get_performance()
  
  if perf_config.enabled then
    M.enable()
  end
  
  -- Set up auto-commands for performance monitoring
  vim.api.nvim_create_autocmd({'BufEnter', 'BufWinEnter'}, {
    callback = function()
      M.auto_toggle()
    end,
  })
end

return M