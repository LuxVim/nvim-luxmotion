local cursor_animation = require("luxmotion.cursor.animation")
local position_utils = require("luxmotion.utils.position")

local M = {}

function M.smooth_move(direction, count)
  count = count or 1
  local current_pos = position_utils.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = current_line
  local target_col = current_col
  
  if direction == "j" or direction == "k" then
    local buf_info = position_utils.get_buffer_info()
    target_line = position_utils.calculate_target_line(current_line, direction, count, buf_info.line_count)
  elseif direction == "h" or direction == "l" then
    local buf_info = position_utils.get_buffer_info()
    target_col = position_utils.calculate_target_col(current_col, direction, count, #buf_info.current_line)
  end
  
  cursor_animation.animate_cursor(current_line, target_line, current_col, target_col)
end

function M.setup_keymaps()
  vim.keymap.set("n", "j", function()
    M.smooth_move("j", vim.v.count1)
  end, { desc = "Smooth move down" })

  vim.keymap.set("n", "k", function()
    M.smooth_move("k", vim.v.count1)
  end, { desc = "Smooth move up" })

  vim.keymap.set("n", "h", function()
    M.smooth_move("h", vim.v.count1)
  end, { desc = "Smooth move left" })

  vim.keymap.set("n", "l", function()
    M.smooth_move("l", vim.v.count1)
  end, { desc = "Smooth move right" })
end

return M