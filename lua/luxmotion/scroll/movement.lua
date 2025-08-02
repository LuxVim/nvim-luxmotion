local viewport = require("luxmotion.core.viewport")

local M = {}

-- Cached calculations to avoid repeated expensive operations
local calculation_cache = {
  scroll_target = {},
  position_target = {},
  viewport_target = {},
  last_clear = 0,
  cache_duration = 100000000, -- 100ms in nanoseconds
}

local function should_clear_cache()
  local current_time = vim.loop.hrtime()
  if current_time - calculation_cache.last_clear > calculation_cache.cache_duration then
    calculation_cache.scroll_target = {}
    calculation_cache.position_target = {}
    calculation_cache.viewport_target = {}
    calculation_cache.last_clear = current_time
    return true
  end
  return false
end

local function get_cache_key(...)
  return table.concat({...}, "_")
end

function M.calculate_scroll_target(current_line, command, count)
  should_clear_cache()
  
  local cache_key = get_cache_key(current_line, command, count)
  if calculation_cache.scroll_target[cache_key] then
    return calculation_cache.scroll_target[cache_key]
  end
  
  local win_height = viewport.get_height()
  local buf_line_count = viewport.get_line_count()
  local target_line = current_line
  
  if command == "ctrl_d" then
    local scroll_amount = math.floor(win_height / 2) * count
    target_line = current_line + scroll_amount
    if target_line > buf_line_count then
      target_line = buf_line_count
    end
  elseif command == "ctrl_u" then
    local scroll_amount = math.floor(win_height / 2) * count
    target_line = current_line - scroll_amount
    if target_line < 1 then
      target_line = 1
    end
  elseif command == "ctrl_f" then
    local scroll_amount = (win_height - 2) * count
    target_line = current_line + scroll_amount
    if target_line > buf_line_count then
      target_line = buf_line_count
    end
  elseif command == "ctrl_b" then
    local scroll_amount = (win_height - 2) * count
    target_line = current_line - scroll_amount
    if target_line < 1 then
      target_line = 1
    end
  end
  
  calculation_cache.scroll_target[cache_key] = target_line
  return target_line
end

function M.calculate_position_target(current_line, command)
  should_clear_cache()
  
  local cache_key = get_cache_key(current_line, command)
  if calculation_cache.position_target[cache_key] then
    return calculation_cache.position_target[cache_key]
  end
  
  local buf_line_count = viewport.get_line_count()
  local target_line = current_line
  
  if command == "zz" or command == "zt" or command == "zb" then
    target_line = current_line
  elseif command == "gg" then
    target_line = 1
  elseif command == "G" then
    target_line = buf_line_count
  end
  
  calculation_cache.position_target[cache_key] = target_line
  return target_line
end

function M.calculate_viewport_target(target_line, current_topline)
  should_clear_cache()
  
  local cache_key = get_cache_key(target_line, current_topline)
  if calculation_cache.viewport_target[cache_key] then
    return calculation_cache.viewport_target[cache_key]
  end
  
  -- Use the optimized viewport calculation from core module
  local result = viewport.calculate_viewport_target(target_line, current_topline)
  
  calculation_cache.viewport_target[cache_key] = result
  return result
end

-- Cache management functions
function M.clear_cache()
  calculation_cache.scroll_target = {}
  calculation_cache.position_target = {}
  calculation_cache.viewport_target = {}
  calculation_cache.last_clear = vim.loop.hrtime()
end

function M.get_cache_stats()
  return {
    scroll_target_entries = vim.tbl_count(calculation_cache.scroll_target),
    position_target_entries = vim.tbl_count(calculation_cache.position_target),
    viewport_target_entries = vim.tbl_count(calculation_cache.viewport_target),
    last_clear = calculation_cache.last_clear,
  }
end

return M