local scroll_animation = require("luxmotion.scroll.animation")
local position_utils = require("luxmotion.utils.position")

local M = {}

function M.smooth_scroll(command, count)
  count = count or 1
  local current_pos = position_utils.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local win_info = position_utils.get_window_info()
  local buf_info = position_utils.get_buffer_info()
  
  local target_line = position_utils.calculate_scroll_target(
    current_line, 
    command, 
    count, 
    win_info.height, 
    buf_info.line_count
  )
  
  scroll_animation.animate_scroll(current_line, target_line, current_col, current_col)
end

function M.visual_smooth_scroll(command, count)
  count = count or 1
  
  local current_mode = vim.fn.mode()
  local visual_start_pos = vim.fn.getpos("'<")
  local visual_end_pos = vim.fn.getpos("'>")
  
  local current_pos = position_utils.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local win_info = position_utils.get_window_info()
  local buf_info = position_utils.get_buffer_info()
  
  local target_line = position_utils.calculate_scroll_target(
    current_line, 
    command, 
    count, 
    win_info.height, 
    buf_info.line_count
  )
  
  vim.cmd('normal! \\<Esc>')
  
  local restore_visual = function()
    vim.fn.setpos("'<", visual_start_pos)
    vim.fn.setpos("'>", visual_end_pos)
    vim.cmd('normal! gv')
  end
  
  scroll_animation.animate_scroll(current_line, target_line, current_col, current_col, restore_visual)
end

function M.smooth_position(command)
  local current_pos = position_utils.get_cursor_position()
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  local win_info = position_utils.get_window_info()
  local buf_info = position_utils.get_buffer_info()
  
  local target_line = current_line
  
  if command == "zz" then
    target_line = current_line
  elseif command == "zt" then
    target_line = current_line
  elseif command == "zb" then
    target_line = current_line
  elseif command == "gg" then
    target_line = 1
  elseif command == "G" then
    target_line = buf_info.line_count
  end
  
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