local M = {}

function M.get_cursor_position()
  return vim.api.nvim_win_get_cursor(0)
end

function M.get_window_info()
  return {
    height = vim.api.nvim_win_get_height(0),
    topline = vim.fn.line('w0'),
  }
end

function M.get_buffer_info()
  return {
    line_count = vim.api.nvim_buf_line_count(0),
    current_line = vim.api.nvim_get_current_line(),
  }
end

function M.calculate_target_line(current_line, direction, count, buf_line_count)
  if direction == "j" then
    return math.min(current_line + count, buf_line_count)
  elseif direction == "k" then
    return math.max(current_line - count, 1)
  else
    return current_line
  end
end

function M.calculate_target_col(current_col, direction, count, line_length)
  if direction == "h" then
    return math.max(current_col - count, 0)
  elseif direction == "l" then
    return math.min(current_col + count, line_length or 0)
  else
    return current_col
  end
end

function M.calculate_scroll_target(current_line, command, count, win_height, buf_line_count)
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

return M