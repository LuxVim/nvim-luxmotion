local defaults = require("luxmotion.config.defaults")

local M = {}

local current_config = vim.deepcopy(defaults.config)

function M.get()
  return current_config
end

function M.get_cursor()
  return current_config.cursor
end

function M.get_scroll()
  return current_config.scroll
end

function M.get_keymaps()
  return current_config.keymaps
end

function M.update(user_config)
  current_config = vim.tbl_deep_extend("force", current_config, user_config or {})
end

function M.reset()
  current_config = vim.deepcopy(defaults.config)
end

return M