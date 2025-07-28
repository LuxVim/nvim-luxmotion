local M = {}

function M.get_info()
  return {
    line_count = vim.api.nvim_buf_line_count(0),
    current_line = vim.api.nvim_get_current_line(),
  }
end

function M.get_line_count()
  return vim.api.nvim_buf_line_count(0)
end

function M.get_current_line()
  return vim.api.nvim_get_current_line()
end

function M.get_line_length(line_num)
  line_num = line_num or vim.fn.line('.')
  local line = vim.fn.getline(line_num)
  return #line
end

function M.is_valid_line(line_num)
  return line_num >= 1 and line_num <= M.get_line_count()
end

function M.clamp_line(line_num)
  return math.max(1, math.min(line_num, M.get_line_count()))
end

function M.clamp_column(col, line_num)
  line_num = line_num or vim.fn.line('.')
  local line_length = M.get_line_length(line_num)
  return math.max(0, math.min(col, math.max(line_length - 1, 0)))
end

return M