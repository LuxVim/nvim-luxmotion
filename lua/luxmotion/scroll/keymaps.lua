local scroll_animation = require("luxmotion.scroll.animation")
local viewport = require("luxmotion.core.viewport")
local scroll_movement = require("luxmotion.scroll.movement")
local visual_utils = require("luxmotion.utils.visual")

local M = {}

function M.smooth_scroll(command, count)
  count = count or 1
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = scroll_movement.calculate_scroll_target(current_line, command, count)
  
  scroll_animation.animate_scroll(current_line, target_line, current_col, current_col)
end

function M.visual_smooth_scroll(command, count)
  count = count or 1
  
  local selection = visual_utils.save_selection()
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = scroll_movement.calculate_scroll_target(current_line, command, count)
  
  local restore_visual = function()
    visual_utils.exit_visual_mode()
    visual_utils.restore_selection(selection)
  end
  
  scroll_animation.animate_scroll(current_line, target_line, current_col, current_col, restore_visual)
end

function M.smooth_position(command)
  local current_pos = viewport.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local target_line = scroll_movement.calculate_position_target(current_line, command)
  
  scroll_animation.animate_scroll(current_line, target_line, current_col, current_col)
end

function M.setup_keymaps()
  vim.keymap.set("n", "<C-d>", function()
    M.smooth_scroll("ctrl_d", vim.v.count1)
  end, { desc = "Smooth scroll down half-page" })

  vim.keymap.set("n", "<C-u>", function()
    M.smooth_scroll("ctrl_u", vim.v.count1)
  end, { desc = "Smooth scroll up half-page" })

  vim.keymap.set("n", "<C-f>", function()
    M.smooth_scroll("ctrl_f", vim.v.count1)
  end, { desc = "Smooth scroll down full-page" })

  vim.keymap.set("n", "<C-b>", function()
    M.smooth_scroll("ctrl_b", vim.v.count1)
  end, { desc = "Smooth scroll up full-page" })

  vim.keymap.set("v", "<C-d>", function()
    M.visual_smooth_scroll("ctrl_d", vim.v.count1)
  end, { desc = "Smooth scroll down half-page" })

  vim.keymap.set("v", "<C-u>", function()
    M.visual_smooth_scroll("ctrl_u", vim.v.count1)
  end, { desc = "Smooth scroll up half-page" })

  vim.keymap.set("v", "<C-f>", function()
    M.visual_smooth_scroll("ctrl_f", vim.v.count1)
  end, { desc = "Smooth scroll down full-page" })

  vim.keymap.set("v", "<C-b>", function()
    M.visual_smooth_scroll("ctrl_b", vim.v.count1)
  end, { desc = "Smooth scroll up full-page" })

  vim.keymap.set("n", "zz", function()
    M.smooth_position("zz")
  end, { desc = "Center cursor in window" })

  vim.keymap.set("n", "zt", function()
    M.smooth_position("zt")
  end, { desc = "Move cursor to top of window" })

  vim.keymap.set("n", "zb", function()
    M.smooth_position("zb")
  end, { desc = "Move cursor to bottom of window" })
end

return M