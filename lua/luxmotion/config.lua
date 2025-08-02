local management = require("luxmotion.config.management")
local validation = require("luxmotion.config.validation")

local M = {}

M.get = management.get
M.get_cursor = management.get_cursor
M.get_scroll = management.get_scroll
M.get_keymaps = management.get_keymaps
M.get_performance = management.get_performance
M.update = management.update
M.reset = management.reset
M.validate = validation.validate_config

return M