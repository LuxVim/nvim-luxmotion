local M = {}

local state = {
  notifications = {},
  commands = {},
  keymaps = {},
  deleted_keymaps = {},
  deferred_calls = {},
  scheduled_calls = {},
  hrtime_value = 0,
}

function M.reset()
  state = {
    notifications = {},
    commands = {},
    keymaps = {},
    deleted_keymaps = {},
    deferred_calls = {},
    scheduled_calls = {},
    hrtime_value = 0,
  }
end

function M.get_state()
  return state
end

function M.get_notifications()
  return state.notifications
end

function M.get_commands()
  return state.commands
end

function M.get_keymaps()
  return state.keymaps
end

function M.get_deleted_keymaps()
  return state.deleted_keymaps
end

function M.get_deferred_calls()
  return state.deferred_calls
end

function M.execute_deferred(index)
  local call = state.deferred_calls[index]
  if call and call.fn then
    call.fn()
  end
end

function M.set_hrtime(value)
  state.hrtime_value = value
end

function M.advance_hrtime(delta_ns)
  state.hrtime_value = state.hrtime_value + delta_ns
end

M.cmd = function(command)
  table.insert(state.commands, command)
end

M.notify = function(msg, level, opts)
  table.insert(state.notifications, {
    msg = msg,
    level = level,
    opts = opts,
  })
end

M.schedule = function(fn)
  table.insert(state.scheduled_calls, fn)
  fn()
end

M.defer_fn = function(fn, delay)
  table.insert(state.deferred_calls, {
    fn = fn,
    delay = delay,
  })
end

M.keymap = {
  set = function(mode, lhs, rhs, opts)
    local modes = type(mode) == 'table' and mode or { mode }
    for _, m in ipairs(modes) do
      state.keymaps[m .. ':' .. lhs] = {
        mode = m,
        lhs = lhs,
        rhs = rhs,
        opts = opts,
      }
    end
  end,

  del = function(mode, lhs)
    local modes = type(mode) == 'table' and mode or { mode }
    for _, m in ipairs(modes) do
      local key = m .. ':' .. lhs
      if state.keymaps[key] then
        state.keymaps[key] = nil
        table.insert(state.deleted_keymaps, { mode = m, lhs = lhs })
      end
    end
  end,
}

local function deepcopy(orig)
  local copy
  if type(orig) == 'table' then
    copy = {}
    for k, v in pairs(orig) do
      copy[deepcopy(k)] = deepcopy(v)
    end
    setmetatable(copy, deepcopy(getmetatable(orig)))
  else
    copy = orig
  end
  return copy
end

M.deepcopy = deepcopy

M.tbl_deep_extend = function(behavior, ...)
  local result = {}
  for _, tbl in ipairs({ ... }) do
    if type(tbl) == 'table' then
      for k, v in pairs(tbl) do
        if type(v) == 'table' and type(result[k]) == 'table' then
          result[k] = M.tbl_deep_extend(behavior, result[k], v)
        else
          result[k] = deepcopy(v)
        end
      end
    end
  end
  return result
end

M.tbl_keys = function(tbl)
  local keys = {}
  for k, _ in pairs(tbl) do
    table.insert(keys, k)
  end
  return keys
end

M.tbl_contains = function(tbl, val)
  for _, v in ipairs(tbl) do
    if v == val then
      return true
    end
  end
  return false
end

M.loop = {
  hrtime = function()
    state.hrtime_value = state.hrtime_value + 100000000
    return state.hrtime_value
  end,
}

M.options = {
  scrolloff = 5,
  startofline = false,
}

M.buffer_options = {
  syntax = "lua",
  filetype = "lua",
}

M.v = {
  count = 0,
  count1 = 1,
}

return M
