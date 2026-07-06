local M = {}

local function calculate_via_native(cmd, context)
  local original = { context.cursor.line, context.cursor.col }
  vim.api.nvim_win_set_cursor(0, original)

  local success = pcall(vim.cmd, "normal! " .. cmd)

  if not success then
    vim.api.nvim_win_set_cursor(0, original)
    return {
      cursor = { line = context.cursor.line, col = context.cursor.col },
    }
  end

  local target = vim.api.nvim_win_get_cursor(0)
  vim.api.nvim_win_set_cursor(0, original)

  return {
    cursor = { line = target[1], col = target[2] },
  }
end

M["{"] = function(context)
  return calculate_via_native(context.input.count .. "{", context)
end

M["}"] = function(context)
  return calculate_via_native(context.input.count .. "}", context)
end

M["("] = function(context)
  return calculate_via_native(context.input.count .. "(", context)
end

M[")"] = function(context)
  return calculate_via_native(context.input.count .. ")", context)
end

M["%"] = function(context)
  local cmd = "%"
  if context.input.has_count then
    cmd = context.input.count .. "%"
  end
  return calculate_via_native(cmd, context)
end

return M
