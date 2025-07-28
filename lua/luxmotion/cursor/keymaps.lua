local cursor_animation = require("luxmotion.cursor.animation")
local window_utils = require("luxmotion.utils.window")
local cursor_movement = require("luxmotion.cursor.movement")

local M = {}

function M.smooth_move(direction, count)
  count = count or 1
  local current_pos = window_utils.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = cursor_movement.calculate_target_line(current_line, direction, count)
  local target_col = cursor_movement.calculate_target_col(current_col, direction, count, current_line)
  
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

  -- Visual mode keymaps
  vim.keymap.set("v", "j", function()
    M.smooth_move("j", vim.v.count1)
  end, { desc = "Smooth move down (visual)" })

  vim.keymap.set("v", "k", function()
    M.smooth_move("k", vim.v.count1)
  end, { desc = "Smooth move up (visual)" })

  vim.keymap.set("v", "h", function()
    M.smooth_move("h", vim.v.count1)
  end, { desc = "Smooth move left (visual)" })

  vim.keymap.set("v", "l", function()
    M.smooth_move("l", vim.v.count1)
  end, { desc = "Smooth move right (visual)" })

  vim.keymap.set("n", "0", function()
    M.smooth_move("0", 1)
  end, { desc = "Smooth move to beginning of line" })

  vim.keymap.set("n", "$", function()
    M.smooth_move("$", 1)
  end, { desc = "Smooth move to end of line" })

  vim.keymap.set("v", "0", function()
    M.smooth_move("0", 1)
  end, { desc = "Smooth move to beginning of line (visual)" })

  vim.keymap.set("v", "$", function()
    M.smooth_move("$", 1)
  end, { desc = "Smooth move to end of line (visual)" })
end

return M