local viewport = require("luxmotion.core.viewport")

local M = {}

function M.calculate_target_line(current_line, direction, count)
  local buf_line_count = viewport.get_line_count()
  
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
  local line_length = viewport.get_line_length(line_num)
  
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

-- Generic movement target calculator using vim motions
function M.calculate_movement_target(movement_cmd, count)
  count = count or 1
  local current_pos = vim.api.nvim_win_get_cursor(0)
  local current_line = current_pos[1]
  local current_col = current_pos[2]
  
  -- Save cursor position
  vim.api.nvim_win_set_cursor(0, current_pos)
  
  -- Execute movement command to get target position
  local cmd = count .. movement_cmd
  local success, _ = pcall(vim.cmd, "normal! " .. cmd)
  
  if not success then
    -- Restore original position on error
    vim.api.nvim_win_set_cursor(0, current_pos)
    return current_line, current_col
  end
  
  local target_pos = vim.api.nvim_win_get_cursor(0)
  local target_line = target_pos[1]
  local target_col = target_pos[2]
  
  -- Restore original cursor position
  vim.api.nvim_win_set_cursor(0, current_pos)
  
  return target_line, target_col
end

function M.calculate_word_target(direction, count)
  local movement_map = {
    w = "w", b = "b", e = "e",
    W = "W", B = "B", E = "E"
  }
  
  local movement_cmd = movement_map[direction]
  if not movement_cmd then
    local current_pos = vim.api.nvim_win_get_cursor(0)
    return current_pos[1], current_pos[2]
  end
  
  return M.calculate_movement_target(movement_cmd, count)
end

function M.calculate_find_target(direction, char, count)
  count = count or 1
  local movement_map = {
    f = "f" .. char,
    F = "F" .. char, 
    t = "t" .. char,
    T = "T" .. char
  }
  
  local movement_cmd = movement_map[direction]
  if not movement_cmd then
    local current_pos = vim.api.nvim_win_get_cursor(0)
    return current_pos[1], current_pos[2]
  end
  
  return M.calculate_movement_target(movement_cmd, count)
end

function M.calculate_text_object_target(direction, count)
  local movement_map = {
    ["}"] = "}",
    ["{"] = "{",
    [")"] = ")",
    ["("] = "(",
    ["%"] = "%"
  }
  
  local movement_cmd = movement_map[direction]
  if not movement_cmd then
    local current_pos = vim.api.nvim_win_get_cursor(0)
    return current_pos[1], current_pos[2]
  end
  
  return M.calculate_movement_target(movement_cmd, count)
end

function M.calculate_line_target(direction, count)
  if direction == "gg" then
    local line_num = count or 1
    -- Get first non-blank character position
    local line_content = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
    local first_non_blank = line_content:match("^%s*"):len()
    return line_num, first_non_blank
  elseif direction == "G" then
    -- For G without explicit count (vim.v.count == 0), go to last line
    -- For G with explicit count (vim.v.count > 0), go to that line
    local line_num
    if vim.v.count == 0 then
      line_num = viewport.get_line_count()
    else
      line_num = count
    end
    -- Get first non-blank character position for the target line
    local line_content = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
    local first_non_blank = line_content:match("^%s*"):len()
    return line_num, first_non_blank
  elseif direction == "|" then
    local current_pos = vim.api.nvim_win_get_cursor(0)
    local col_num = math.max((count or 1) - 1, 0)
    return current_pos[1], col_num
  end
  
  local current_pos = vim.api.nvim_win_get_cursor(0)
  return current_pos[1], current_pos[2]
end

function M.calculate_search_target(direction, count)
  return M.calculate_movement_target(direction, count)
end

function M.calculate_screen_line_target(direction, count)
  return M.calculate_movement_target(direction, count)
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