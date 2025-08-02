-- Consolidated animation module 
-- Combines functionality from utils/animation.lua and utils/math.lua
local M = {}

-- Math utilities (formerly from utils/math.lua)
function M.lerp(start_val, end_val, progress)
  return start_val + (end_val - start_val) * progress
end

function M.clamp(value, min_val, max_val)
  return math.max(min_val, math.min(value, max_val))
end

-- Easing functions
local easing_functions = {
  linear = function(t) return t end,
  ["ease-in"] = function(t) return t * t end,
  ["ease-out"] = function(t) return 1 - (1 - t) * (1 - t) end,
  ["ease-in-out"] = function(t)
    if t < 0.5 then
      return 2 * t * t
    else
      return 1 - 2 * (1 - t) * (1 - t)
    end
  end,
}

function M.get_easing_function(easing_type)
  return easing_functions[easing_type] or easing_functions.linear
end

-- Optimized animation system using vim.defer_fn with pooling
local frame_queue = {}
local is_running = false

-- Animation object pool for memory efficiency
local animation_pool = {}
local pool_size = 0
local MAX_POOL_SIZE = 10

local function get_pooled_animation()
  if pool_size > 0 then
    pool_size = pool_size - 1
    return table.remove(animation_pool)
  else
    return {
      start_time = 0,
      duration_ns = 0,
      easing_fn = nil,
      update_fn = nil,
      complete_fn = nil,
      completed = false
    }
  end
end

local function return_to_pool(animation)
  if pool_size < MAX_POOL_SIZE then
    animation.completed = false
    animation.start_time = 0
    animation.duration_ns = 0
    animation.easing_fn = nil
    animation.update_fn = nil
    animation.complete_fn = nil
    pool_size = pool_size + 1
    table.insert(animation_pool, animation)
  end
end

local function process_frame_queue()
  local current_time = vim.loop.hrtime()
  
  -- Performance monitoring
  local performance = require("luxmotion.performance")
  performance.record_frame_time()
  
  for i = #frame_queue, 1, -1 do
    local animation = frame_queue[i]
    if not animation.completed then
      local elapsed = current_time - animation.start_time
      local progress = math.min(elapsed / animation.duration_ns, 1.0)
      
      local eased_progress = animation.easing_fn(progress)
      animation.update_fn(eased_progress, progress)
      
      if progress >= 1.0 then
        animation.completed = true
        animation.complete_fn()
        table.remove(frame_queue, i)
        return_to_pool(animation)
      end
    else
      table.remove(frame_queue, i)
      return_to_pool(animation)
    end
  end
  
  -- Continue processing if animations remain
  if #frame_queue > 0 then
    local performance = require("luxmotion.performance")
    local frame_interval = performance.get_frame_interval()
    vim.defer_fn(process_frame_queue, frame_interval)
  else
    is_running = false
  end
end

function M.create_loop(start_time, duration_ns, easing_fn, update_fn, complete_fn)
  local animation = get_pooled_animation()
  animation.start_time = start_time
  animation.duration_ns = duration_ns
  animation.easing_fn = easing_fn
  animation.update_fn = update_fn
  animation.complete_fn = complete_fn
  animation.completed = false
  
  table.insert(frame_queue, animation)
  
  -- Start processing if not already running
  if not is_running then
    is_running = true
    local performance = require("luxmotion.performance")
    local frame_interval = performance.get_frame_interval()
    vim.defer_fn(process_frame_queue, frame_interval)
  end
  
  -- Return immediate function for compatibility
  return function() end
end

function M.interpolate_values(start_val, end_val, eased_progress)
  return math.floor(M.lerp(start_val, end_val, eased_progress) + 0.5)
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

-- Animation state management
function M.get_active_animation_count()
  return #frame_queue
end

function M.stop_all_animations()
  for _, animation in ipairs(frame_queue) do
    return_to_pool(animation)
  end
  frame_queue = {}
  is_running = false
end

-- Performance utilities
function M.get_pool_stats()
  return {
    pool_size = pool_size,
    active_animations = #frame_queue,
    max_pool_size = MAX_POOL_SIZE
  }
end

return M