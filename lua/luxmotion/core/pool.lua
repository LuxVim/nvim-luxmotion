-- Enhanced object pooling system for various data structures
local M = {}

-- Generic object pool implementation
local function create_pool(factory_fn, reset_fn, max_size)
  max_size = max_size or 10
  
  local pool = {
    objects = {},
    size = 0,
    max_size = max_size,
    factory = factory_fn,
    reset = reset_fn or function() end,
    hits = 0,
    misses = 0,
  }
  
  function pool:get()
    if self.size > 0 then
      self.size = self.size - 1
      self.hits = self.hits + 1
      return table.remove(self.objects)
    else
      self.misses = self.misses + 1
      return self.factory()
    end
  end
  
  function pool:return(obj)
    if self.size < self.max_size then
      self.reset(obj)
      self.size = self.size + 1
      table.insert(self.objects, obj)
      return true
    end
    return false
  end
  
  function pool:stats()
    return {
      size = self.size,
      hits = self.hits,
      misses = self.misses,
      hit_rate = self.hits / (self.hits + self.misses)
    }
  end
  
  function pool:clear()
    self.objects = {}
    self.size = 0
  end
  
  return pool
end

-- Viewport info pool
local viewport_info_pool = create_pool(
  function()
    return {
      height = 0,
      width = 0,
      topline = 0,
      line_count = 0,
    }
  end,
  function(obj)
    obj.height = 0
    obj.width = 0
    obj.topline = 0
    obj.line_count = 0
  end,
  15
)

-- Cursor position pool
local cursor_pos_pool = create_pool(
  function()
    return {0, 0}
  end,
  function(obj)
    obj[1] = 0
    obj[2] = 0
  end,
  20
)

-- Animation step cache pool
local step_cache_pool = create_pool(
  function()
    return {}
  end,
  function(obj)
    for k in pairs(obj) do
      obj[k] = nil
    end
  end,
  5
)

-- Public API
function M.get_viewport_info()
  return viewport_info_pool:get()
end

function M.return_viewport_info(obj)
  return viewport_info_pool:return(obj)
end

function M.get_cursor_pos()
  return cursor_pos_pool:get()
end

function M.return_cursor_pos(obj)
  return cursor_pos_pool:return(obj)
end

function M.get_step_cache()
  return step_cache_pool:get()
end

function M.return_step_cache(obj)
  return step_cache_pool:return(obj)
end

-- Statistics and management
function M.get_stats()
  return {
    viewport_info = viewport_info_pool:stats(),
    cursor_pos = cursor_pos_pool:stats(),
    step_cache = step_cache_pool:stats(),
  }
end

function M.clear_all_pools()
  viewport_info_pool:clear()
  cursor_pos_pool:clear()
  step_cache_pool:clear()
end

-- Memory cleanup
function M.cleanup()
  M.clear_all_pools()
  collectgarbage("collect")
end

return M