local M = {}

function M.get_info()
  return {
    height = vim.api.nvim_win_get_height(0),
    width = vim.api.nvim_win_get_width(0),
    topline = vim.fn.line('w0'),
  }
end

function M.get_height()
  return vim.api.nvim_win_get_height(0)
end

function M.get_width()
  return vim.api.nvim_win_get_width(0)
end

function M.get_topline()
  return vim.fn.line('w0')
end

function M.get_cursor_position()
  return vim.api.nvim_win_get_cursor(0)
end

function M.set_cursor_position(line, col)
  vim.api.nvim_win_set_cursor(0, {line, col})
end

function M.get_scrolloff()
  return vim.o.scrolloff
end

function M.restore_view(topline, line, col)
  vim.fn.winrestview({
    topline = topline,
    lnum = line,
    col = col,
    leftcol = 0
  })
end

function M.calculate_topline_for_center(target_line, buf_line_count)
  local win_height = M.get_height()
  local topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(topline, buf_line_count - win_height + 1))
end

return M