local buffer_utils = require("luxmotion.utils.buffer")
local window_utils = require("luxmotion.utils.window")

local M = {}

function M.calculate_scroll_target(current_line, command, count)
  local win_height = window_utils.get_height()
  local buf_line_count = buffer_utils.get_line_count()
  local target_line = current_line
  
  if command == "ctrl_d" then
    local scroll_amount = math.floor(win_height / 2) * count
    target_line = current_line + scroll_amount
    if target_line > buf_line_count then
      target_line = buf_line_count
    end
  elseif command == "ctrl_u" then
    local scroll_amount = math.floor(win_height / 2) * count
    target_line = current_line - scroll_amount
    if target_line < 1 then
      target_line = 1
    end
  elseif command == "ctrl_f" then
    local scroll_amount = (win_height - 2) * count
    target_line = current_line + scroll_amount
    if target_line > buf_line_count then
      target_line = buf_line_count
    end
  elseif command == "ctrl_b" then
    local scroll_amount = (win_height - 2) * count
    target_line = current_line - scroll_amount
    if target_line < 1 then
      target_line = 1
    end
  end
  
  return target_line
end

function M.calculate_position_target(current_line, command)
  local buf_line_count = buffer_utils.get_line_count()
  
  if command == "zz" or command == "zt" or command == "zb" then
    return current_line
  elseif command == "gg" then
    return 1
  elseif command == "G" then
    return buf_line_count
  end
  
  return current_line
end

function M.calculate_viewport_target(target_line, current_topline)
  local win_height = window_utils.get_height()
  local buf_line_count = buffer_utils.get_line_count()
  
  local target_topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(target_topline, buf_line_count - win_height + 1))
end

return M