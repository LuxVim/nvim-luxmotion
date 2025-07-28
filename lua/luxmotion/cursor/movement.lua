local buffer_utils = require("luxmotion.utils.buffer")

local M = {}

function M.calculate_target_line(current_line, direction, count)
  local buf_line_count = buffer_utils.get_line_count()
  
  if direction == "j" then
    return math.min(current_line + count, buf_line_count)
  elseif direction == "k" then
    return math.max(current_line - count, 1)
  else
    return current_line
  end
end

function M.calculate_target_col(current_col, direction, count, line_num)
  line_num = line_num or vim.fn.line('.')
  local line_length = buffer_utils.get_line_length(line_num)
  
  if direction == "h" then
    return math.max(current_col - count, 0)
  elseif direction == "l" then
    return math.min(current_col + count, line_length)
  elseif direction == "0" then
    return 0
  elseif direction == "$" then
    return math.max(line_length - 1, 0)
  else
    return current_col
  end
end

function M.calculate_movement_duration(base_duration, start_line, end_line, start_col, end_col)
  local line_distance = math.abs(end_line - start_line)
  local col_distance = math.abs(end_col - start_col)
  
  if line_distance <= 1 and col_distance <= 1 then
    return math.floor(base_duration * 0.2)
  elseif line_distance <= 3 or col_distance <= 3 then
    return math.floor(base_duration * 0.4)
  elseif start_line == end_line and start_col ~= end_col then
    return math.floor(base_duration * 0.6)
  end
  
  return base_duration
end

return M