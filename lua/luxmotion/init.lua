local config = require("luxmotion.config")
local cursor_keymaps = require("luxmotion.cursor.keymaps")
local scroll_keymaps = require("luxmotion.scroll.keymaps")
local experimental_keymaps = require("luxmotion.experimental.keymaps")

local M = {}

function M.setup(user_config)
  config.validate(user_config)
  config.update(user_config)
  
  -- Initialize performance monitoring
  local performance = require("luxmotion.performance")
  performance.setup()
  
  local keymap_config = config.get_keymaps()
  
  if keymap_config.cursor then
    cursor_keymaps.setup_keymaps()
  end
  
  if keymap_config.scroll then
    scroll_keymaps.setup_keymaps()
  end
  
  if keymap_config.experimental then
    experimental_keymaps.setup_keymaps()
  end
end

function M.enable()
  local current_config = config.get()
  config.update({
    cursor = { enabled = true },
    scroll = { enabled = true }
  })
end

function M.disable()
  local current_config = config.get()
  config.update({
    cursor = { enabled = false },
    scroll = { enabled = false }
  })
end

function M.toggle()
  local current_config = config.get()
  local cursor_enabled = current_config.cursor.enabled
  local scroll_enabled = current_config.scroll.enabled
  
  if cursor_enabled or scroll_enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.enable_cursor()
  config.update({ cursor = { enabled = true } })
end

function M.disable_cursor()
  config.update({ cursor = { enabled = false } })
end

function M.enable_scroll()
  config.update({ scroll = { enabled = true } })
end

function M.disable_scroll()
  config.update({ scroll = { enabled = false } })
end

function M.move_smooth(direction, count)
  cursor_keymaps.smooth_move(direction, count)
end

function M.scroll_smooth(command, count)
  scroll_keymaps.smooth_scroll(command, count)
end

function M.toggle_performance()
  local performance = require("luxmotion.performance")
  if performance.is_active() then
    performance.disable()
  else
    performance.enable()
  end
end

return M