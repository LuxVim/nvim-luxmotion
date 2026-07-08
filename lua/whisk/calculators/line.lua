local M = {}

local function get_first_non_blank(line_num)
  local line_content = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1] or ""
  local leading_space = line_content:match("^%s*")
  return leading_space and #leading_space or 0
end

local function get_target_col(context, target_line)
  if vim.o.startofline then
    return get_first_non_blank(target_line)
  end
  local line_content = vim.api.nvim_buf_get_lines(0, target_line - 1, target_line, false)[1] or ""
  local max_col = math.max(#line_content - 1, 0)
  return math.max(0, math.min(context.cursor.col, max_col))
end

local function calculate_topline(target_line, context)
  local win_height = context.viewport.height
  local topline = target_line - math.floor(win_height / 2)
  return math.max(1, math.min(topline, context.buffer.line_count - win_height + 1))
end

function M.gg(context)
  local target_line = context.input.count
  target_line = math.max(1, math.min(target_line, context.buffer.line_count))
  local target_col = get_target_col(context, target_line)

  return {
    cursor = { line = target_line, col = target_col },
    viewport = { topline = calculate_topline(target_line, context) },
  }
end

function M.G(context)
  local target_line
  if not context.input.has_count then
    target_line = context.buffer.line_count
  else
    target_line = math.max(1, math.min(context.input.count, context.buffer.line_count))
  end
  local target_col = get_target_col(context, target_line)

  return {
    cursor = { line = target_line, col = target_col },
    viewport = { topline = calculate_topline(target_line, context) },
  }
end

M["|"] = function(context)
  local target_col = math.max(context.input.count - 1, 0)
  return {
    cursor = { line = context.cursor.line, col = target_col },
  }
end

return M
